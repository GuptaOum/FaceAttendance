from datetime import date, datetime

from fastapi import APIRouter, Depends, File, HTTPException, Request, UploadFile, status

from ..db import get_db
from ..security import get_current_user, require_teacher

router = APIRouter(prefix="/attendance", tags=["attendance"])


@router.delete("/{attendance_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_attendance(attendance_id: int, user: dict = Depends(require_teacher)):
    with get_db() as conn:
        row = conn.execute(
            """SELECT a.id FROM attendance a JOIN students s ON s.id = a.student_id
               WHERE a.id = ? AND s.owner_id = ?""",
            (attendance_id, user["id"]),
        ).fetchone()
        if row is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Attendance record not found")
        conn.execute("DELETE FROM attendance WHERE id = ?", (attendance_id,))


def _session_phase(sess) -> str | None:
    now = datetime.now().strftime("%H:%M")
    if sess["start_time"] <= now <= sess["entry_until"]:
        return "entry"
    if sess["exit_from"] <= now <= sess["exit_until"]:
        return "exit"
    return None


def _group_ids(conn, owner_id: int, group: str) -> set[int]:
    rows = conn.execute(
        "SELECT id FROM students WHERE owner_id = ? AND class_name = ?", (owner_id, group)
    ).fetchall()
    return {r["id"] for r in rows}


@router.post("/recognize")
async def recognize(
    request: Request,
    image: UploadFile = File(...),
    group: str | None = None,
    session_id: int | None = None,
    user: dict = Depends(require_teacher),
):
    engine = request.app.state.engine
    today = date.today().isoformat()

    sess = None
    phase = None
    if session_id is not None:
        with get_db() as conn:
            sess = conn.execute(
                "SELECT * FROM sessions WHERE id = ? AND owner_id = ?", (session_id, user["id"])
            ).fetchone()
        if sess is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Session not found")
        if sess["date"] != today:
            return {"matched": False, "reason": "wrong_day", "session_date": sess["date"]}
        phase = _session_phase(sess)
        if phase is None:
            return {
                "matched": False, "reason": "window_closed",
                "entry_window": f"{sess['start_time']}-{sess['entry_until']}",
                "exit_window": f"{sess['exit_from']}-{sess['exit_until']}",
            }
        group = sess["group_name"] or None

    embedding, reason = engine.embed_kiosk_face(await image.read())
    if embedding is None:
        return {"matched": False, "reason": reason}

    allowed_ids = None
    if group:
        with get_db() as conn:
            allowed_ids = _group_ids(conn, user["id"], group)

    result = engine.match(embedding, owner_id=user["id"], allowed_ids=allowed_ids)
    if result is None:
        return {"matched": False, "reason": "unknown_face"}

    student_id, confidence = result
    with get_db() as conn:
        student = conn.execute("SELECT * FROM students WHERE id = ?", (student_id,)).fetchone()
        student_out = {"id": student["id"], "roll_no": student["roll_no"], "name": student["name"]}

        if sess is None:
            already = conn.execute(
                "SELECT marked_at FROM attendance WHERE student_id = ? AND date = ? AND session_id IS NULL",
                (student_id, today),
            ).fetchone()
            if already is None:
                conn.execute(
                    "INSERT INTO attendance (student_id, date, confidence) VALUES (?, ?, ?)",
                    (student_id, today, confidence),
                )
            return {
                "matched": True, "student": student_out, "confidence": round(confidence, 3),
                "already_marked": already is not None,
                "marked_at": already["marked_at"] if already else None,
            }

        row = conn.execute(
            "SELECT * FROM attendance WHERE student_id = ? AND session_id = ?",
            (student_id, session_id),
        ).fetchone()

        if phase == "entry":
            if row is not None:
                return {
                    "matched": True, "student": student_out, "phase": "entry",
                    "event": "entry_already", "marked_at": row["marked_at"],
                }
            conn.execute(
                "INSERT INTO attendance (student_id, session_id, date, confidence) VALUES (?, ?, ?, ?)",
                (student_id, session_id, today, confidence),
            )
            return {
                "matched": True, "student": student_out, "phase": "entry",
                "event": "entry_marked", "confidence": round(confidence, 3),
            }

        if row is None:
            return {
                "matched": True, "student": student_out, "phase": "exit", "event": "no_entry",
            }
        if row["exit_at"] is not None:
            return {
                "matched": True, "student": student_out, "phase": "exit",
                "event": "exit_already", "exit_at": row["exit_at"],
            }
        conn.execute(
            "UPDATE attendance SET exit_at = datetime('now', 'localtime') WHERE id = ?",
            (row["id"],),
        )
        return {
            "matched": True, "student": student_out, "phase": "exit",
            "event": "exit_marked", "confidence": round(confidence, 3),
        }


@router.get("")
def attendance_report(
    day: str | None = None,
    group: str | None = None,
    session_id: int | None = None,
    user: dict = Depends(require_teacher),
):
    target = day or date.today().isoformat()
    with get_db() as conn:
        if session_id is not None:
            sess = conn.execute(
                "SELECT * FROM sessions WHERE id = ? AND owner_id = ?", (session_id, user["id"])
            ).fetchone()
            if sess is None:
                raise HTTPException(status.HTTP_404_NOT_FOUND, "Session not found")
            present = conn.execute(
                """SELECT s.id, s.roll_no, s.name, s.class_name, a.marked_at, a.exit_at,
                          a.confidence, a.id AS attendance_id
                   FROM attendance a JOIN students s ON s.id = a.student_id
                   WHERE a.session_id = ? ORDER BY a.marked_at""",
                (session_id,),
            ).fetchall()
            group_filter = " AND class_name = :group" if sess["group_name"] else ""
            absent = conn.execute(
                f"""SELECT id, roll_no, name, class_name FROM students
                   WHERE owner_id = :owner{group_filter}
                     AND id NOT IN (SELECT student_id FROM attendance WHERE session_id = :sid)
                   ORDER BY roll_no""",
                {"owner": user["id"], "group": sess["group_name"], "sid": session_id},
            ).fetchall()
            return {
                "date": sess["date"], "session": dict(sess),
                "present": [dict(r) for r in present],
                "absent": [dict(r) for r in absent],
            }

        group_filter = " AND s.class_name = :group" if group else ""
        params = {"target": target, "owner": user["id"], "group": group}
        present = conn.execute(
            f"""SELECT s.id, s.roll_no, s.name, s.class_name, a.marked_at, a.exit_at,
                      a.confidence, a.id AS attendance_id, a.session_id
               FROM attendance a JOIN students s ON s.id = a.student_id
               WHERE a.date = :target AND s.owner_id = :owner{group_filter} ORDER BY a.marked_at""",
            params,
        ).fetchall()
        absent = conn.execute(
            f"""SELECT s.id, s.roll_no, s.name, s.class_name FROM students s
               WHERE s.owner_id = :owner{group_filter}
                 AND s.id NOT IN (SELECT student_id FROM attendance WHERE date = :target)
               ORDER BY s.roll_no""",
            params,
        ).fetchall()
    return {"date": target, "present": [dict(r) for r in present], "absent": [dict(r) for r in absent]}


@router.get("/me")
def my_attendance(user: dict = Depends(get_current_user)):
    with get_db() as conn:
        rows = conn.execute(
            """SELECT a.date, a.marked_at, a.exit_at, a.confidence
               FROM attendance a JOIN students s ON s.id = a.student_id
               JOIN users u ON u.username = s.roll_no
               WHERE u.username = ? ORDER BY a.date DESC LIMIT 90""",
            (user["username"],),
        ).fetchall()
    return [dict(r) for r in rows]
