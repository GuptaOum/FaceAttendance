from datetime import date as date_cls

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from ..db import get_db
from ..notify import PHONE_RE, SendError, get_sender, render_absence
from ..security import require_teacher

router = APIRouter(prefix="/notifications", tags=["notifications"])


class NotifyAbsentIn(BaseModel):
    # Explicit approval list. There is deliberately no "send to everyone absent"
    # shortcut: a teacher must name the students whose parents get a message.
    student_ids: list[int] = Field(..., min_length=1)
    date: str | None = None
    session_id: int | None = None


def _resolve_absent(conn, user: dict, target: str, session_id: int | None):
    """Students the teacher owns who have no attendance row for this day/session."""
    if session_id is not None:
        sess = conn.execute(
            "SELECT * FROM sessions WHERE id = ? AND owner_id = ?", (session_id, user["id"])
        ).fetchone()
        if sess is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Session not found")
        group_filter = " AND class_name = :group" if sess["group_name"] else ""
        rows = conn.execute(
            f"""SELECT id, roll_no, name, class_name, parent_phone FROM students
                WHERE owner_id = :owner{group_filter}
                  AND id NOT IN (SELECT student_id FROM attendance WHERE session_id = :sid)
                ORDER BY roll_no""",
            {"owner": user["id"], "group": sess["group_name"], "sid": session_id},
        ).fetchall()
        return rows, sess["date"], sess["title"]
    rows = conn.execute(
        """SELECT id, roll_no, name, class_name, parent_phone FROM students
           WHERE owner_id = :owner
             AND id NOT IN (SELECT student_id FROM attendance WHERE date = :target)
           ORDER BY roll_no""",
        {"owner": user["id"], "target": target},
    ).fetchall()
    return rows, target, "the full day"


@router.get("/absent")
def preview_absent(
    date: str | None = None, session_id: int | None = None, user: dict = Depends(require_teacher)
):
    """Who would be messaged, and why some cannot be. Sends nothing."""
    target = date or date_cls.today().isoformat()
    with get_db() as conn:
        rows, target, label = _resolve_absent(conn, user, target, session_id)
        already = {
            r["student_id"]
            for r in conn.execute(
                "SELECT student_id FROM notifications WHERE date = ? AND status = 'sent'",
                (target,),
            ).fetchall()
        }
    out = []
    for r in rows:
        student = dict(r)
        if not student["parent_phone"]:
            student["notifiable"] = False
            student["blocked_reason"] = "No parent phone on file"
        elif not PHONE_RE.match(student["parent_phone"]):
            student["notifiable"] = False
            student["blocked_reason"] = "Parent phone is not valid E.164 (e.g. +919876543210)"
        elif r["id"] in already:
            student["notifiable"] = False
            student["blocked_reason"] = "Parent already notified for this date"
        else:
            student["notifiable"] = True
            student["preview"] = render_absence(student, target, label)
        out.append(student)
    sender = None
    try:
        sender = get_sender()
    except SendError:
        pass
    return {
        "date": target,
        "label": label,
        "provider": getattr(sender, "name", "misconfigured"),
        "will_actually_send": getattr(sender, "sends_for_real", False),
        "absent": out,
    }


@router.post("/absent/send")
def send_absent(body: NotifyAbsentIn, user: dict = Depends(require_teacher)):
    target = body.date or date_cls.today().isoformat()
    try:
        sender = get_sender()
    except SendError as exc:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, str(exc)) from exc

    with get_db() as conn:
        rows, target, label = _resolve_absent(conn, user, target, body.session_id)
        by_id = {r["id"]: dict(r) for r in rows}
        already = {
            r["student_id"]
            for r in conn.execute(
                "SELECT student_id FROM notifications WHERE date = ? AND status = 'sent'",
                (target,),
            ).fetchall()
        }

    results = []
    for student_id in body.student_ids:
        student = by_id.get(student_id)
        if student is None:
            results.append({"student_id": student_id, "status": "skipped",
                            "reason": "Not absent for this date, or not your student"})
            continue
        phone = student["parent_phone"]
        if not phone or not PHONE_RE.match(phone):
            results.append({"student_id": student_id, "status": "skipped",
                            "reason": "Missing or invalid parent phone"})
            continue
        if student_id in already:
            results.append({"student_id": student_id, "status": "skipped",
                            "reason": "Parent already notified for this date"})
            continue

        message = render_absence(student, target, label)
        try:
            ref = sender.send(phone, message)
            row_status, error = ("sent" if sender.sends_for_real else "dry_run"), None
        except SendError as exc:
            ref, row_status, error = None, "failed", str(exc)

        with get_db() as conn:
            conn.execute(
                """INSERT INTO notifications
                   (student_id, session_id, date, to_phone, body, status, provider,
                    provider_ref, error, sent_by)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (student_id, body.session_id, target, phone, message, row_status,
                 sender.name, ref, error, user["id"]),
            )
        results.append({"student_id": student_id, "roll_no": student["roll_no"],
                        "status": row_status, "reason": error})

    counts: dict[str, int] = {}
    for r in results:
        counts[r["status"]] = counts.get(r["status"], 0) + 1
    return {"date": target, "provider": sender.name,
            "actually_sent": sender.sends_for_real, "counts": counts, "results": results}


@router.get("")
def list_notifications(date: str | None = None, user: dict = Depends(require_teacher)):
    query = """SELECT n.id, n.date, n.to_phone, n.body, n.status, n.provider,
                      n.provider_ref, n.error, n.created_at, s.roll_no, s.name
               FROM notifications n JOIN students s ON s.id = n.student_id
               WHERE s.owner_id = ?"""
    params: list = [user["id"]]
    if date:
        query += " AND n.date = ?"
        params.append(date)
    query += " ORDER BY n.created_at DESC LIMIT 200"
    with get_db() as conn:
        rows = conn.execute(query, params).fetchall()
    return [dict(r) for r in rows]
