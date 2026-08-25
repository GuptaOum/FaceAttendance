from datetime import date, datetime, timedelta

from fastapi import APIRouter, Depends, File, HTTPException, Request, UploadFile, status
from pydantic import BaseModel

from .. import config
from ..db import get_db
from ..periods import late_entry_window, same_period as _same_period, summarise
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
    """Which scan the kiosk should record right now.

    'entry'      - on time, inside the entry buffer
    'late_entry' - block already running; still admitted, but the periods that
                   finished before they walked in are not credited
    'exit'       - inside the exit buffer
    """
    now = datetime.now().strftime("%H:%M")
    # Students queue up before the bell; opening the door a little early means
    # an early arrival can still be recorded instead of being turned away.
    try:
        opens = (datetime.strptime(sess["start_time"], "%H:%M")
                 - timedelta(minutes=config.EARLY_ENTRY_MINUTES)).strftime("%H:%M")
    except ValueError:
        opens = sess["start_time"]
    if opens > sess["start_time"]:  # would have wrapped past midnight
        opens = "00:00"

    if opens <= now <= sess["entry_until"]:
        return "entry"
    if sess["exit_from"] <= now <= sess["exit_until"]:
        return "exit"
    if sess["entry_until"] < now < sess["exit_from"]:
        return "late_entry"
    return None


def _minutes_between(marked_at: str, now: datetime) -> float:
    """Minutes since the entry scan. Guards against a double-tap at the kiosk
    being read as the student leaving two seconds after arriving."""
    text = (marked_at or "").strip()
    if " " in text:
        text = text.split(" ", 1)[1]
    try:
        t = datetime.strptime(text[:8], "%H:%M:%S")
    except ValueError:
        try:
            t = datetime.strptime(text[:5], "%H:%M")
        except ValueError:
            return 0.0
    entered = t.hour * 60 + t.minute + t.second / 60
    current = now.hour * 60 + now.minute + now.second / 60
    return current - entered

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

        # A late arrival may only join at the start of a period. Turning up
        # halfway through a class does not earn it, so they wait for the next
        # one rather than being admitted and quietly credited.
        if phase == "late_entry" and row is None:
            periods = conn.execute(
                "SELECT * FROM periods WHERE session_id = ? ORDER BY seq", (session_id,)
            ).fetchall()
            if periods:
                gate = late_entry_window(
                    [dict(p) for p in periods],
                    datetime.now().strftime("%H:%M"),
                    sess["period_entry_grace"] or config.PERIOD_ENTRY_GRACE_MINUTES,
                )
                if not gate["allowed"]:
                    return {
                        "matched": True, "student": student_out,
                        "phase": "late_entry", "event": "period_entry_closed",
                        "missed_period": gate["period"],
                        "next_entry_at": gate["next_at"],
                        "next_entry_closes": gate["closes_at"],
                    }

        if phase in ("entry", "late_entry"):
            if row is not None:
                # Already scanned in. A second scan well into the block is
                # someone leaving early - feeling ill, called away - not a
                # duplicate entry. Recording it as an early exit is what lets
                # them keep the periods they actually sat through; refusing it
                # would cost them the whole block.
                minutes_in = _minutes_between(row["marked_at"], datetime.now())
                now_hhmm = datetime.now().strftime("%H:%M")
                periods = conn.execute(
                    "SELECT * FROM periods WHERE session_id = ? ORDER BY seq", (session_id,)
                ).fetchall()
                # Scanning out inside the same period you scanned into earns
                # nothing, so refuse it and say why. Sitting through the class
                # is the point; a scan at each end of five minutes is not.
                same_period = _same_period(
                    [dict(p) for p in periods], row["marked_at"], now_hhmm
                )
                if row["exit_at"] is None and same_period is not None:
                    return {
                        "matched": True, "student": student_out,
                        "phase": "same_period", "event": "same_period_scan",
                        "period": same_period["subject"],
                        "period_ends": same_period["end_time"],
                        "marked_at": row["marked_at"],
                    }
                if row["exit_at"] is None and minutes_in >= config.MIN_DWELL_MINUTES:
                    conn.execute(
                        "UPDATE attendance SET exit_at = datetime('now', 'localtime') WHERE id = ?",
                        (row["id"],),
                    )
                    periods = conn.execute(
                        "SELECT * FROM periods WHERE session_id = ? ORDER BY seq", (session_id,)
                    ).fetchall()
                    exit_ts = datetime.now().strftime("%H:%M")
                    return {
                        "matched": True, "student": student_out, "phase": "early_exit",
                        "event": "early_exit_marked", "confidence": round(confidence, 3),
                        "period_summary": summarise(
                            periods, row["marked_at"], exit_ts, sess["end_time"]
                        ) if periods else None,
                    }
                return {
                    "matched": True, "student": student_out, "phase": phase,
                    "event": "entry_already", "marked_at": row["marked_at"],
                }
            conn.execute(
                "INSERT INTO attendance (student_id, session_id, date, confidence) VALUES (?, ?, ?, ?)",
                (student_id, session_id, today, confidence),
            )
            # Tell a late arrival exactly which periods they have forfeited,
            # rather than silently crediting or silently dropping the block.
            periods = conn.execute(
                "SELECT * FROM periods WHERE session_id = ? ORDER BY seq", (session_id,)
            ).fetchall()
            out = {
                "matched": True, "student": student_out, "phase": phase,
                "event": "late_entry_marked" if phase == "late_entry" else "entry_marked",
                "confidence": round(confidence, 3),
            }
            if periods:
                now_ts = datetime.now().strftime("%H:%M")
                out["period_summary"] = summarise(periods, now_ts, None, sess["end_time"])
            return out

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
        # The exit scan is what converts the block into counted attendance, so
        # report the final per-period result back to the kiosk.
        periods = conn.execute(
            "SELECT * FROM periods WHERE session_id = ? ORDER BY seq", (session_id,)
        ).fetchall()
        exit_ts = datetime.now().strftime("%H:%M")
        return {
            "matched": True, "student": student_out, "phase": "exit",
            "event": "exit_marked", "confidence": round(confidence, 3),
            "period_summary": summarise(periods, row["marked_at"], exit_ts, sess["end_time"])
                              if periods else None,
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
    """A student's own attendance. Read-only; students have no other endpoint.

    Scoped by students.user_id rather than matching username to roll_no: roll
    numbers are only unique per teacher, so name-matching would show a student
    the records of a same-numbered student belonging to a different teacher.
    """
    with get_db() as conn:
        rows = conn.execute(
            """SELECT s.roll_no, s.name, s.class_name,
                      a.date, a.marked_at, a.exit_at, a.confidence, a.session_id,
                      ses.title AS session_title, ses.end_time AS block_end
               FROM attendance a JOIN students s ON s.id = a.student_id
               LEFT JOIN sessions ses ON ses.id = a.session_id
               WHERE s.user_id = ? ORDER BY a.date DESC, a.marked_at DESC LIMIT 120""",
            (user["id"],),
        ).fetchall()
        out = []
        for r in rows:
            rec = dict(r)
            if r["session_id"] is not None:
                periods = conn.execute(
                    "SELECT * FROM periods WHERE session_id = ? ORDER BY seq",
                    (r["session_id"],),
                ).fetchall()
                if periods:
                    # A roll call the student was missing from ends their
                    # presence there, whatever the exit scan later said.
                    failed = conn.execute(
                        """SELECT MIN(c.checked_at) AS at
                           FROM spot_check_absences a JOIN spot_checks c ON c.id = a.spot_check_id
                           WHERE c.session_id = ? AND a.student_id = (
                               SELECT id FROM students WHERE user_id = ?)""",
                        (r["session_id"], user["id"]),
                    ).fetchone()
                    rec["period_summary"] = summarise(
                        periods, r["marked_at"], r["exit_at"], r["block_end"] or "",
                        failed_spot_check_at=failed["at"] if failed else None,
                    )
            out.append(rec)
    return out


class AttendanceOverride(BaseModel):
    """Teacher correction for a block the scans got wrong."""
    exit_at: str | None = None
    note: str = ""


@router.patch("/{attendance_id}")
def override_attendance(
    attendance_id: int, body: AttendanceOverride, user: dict = Depends(require_teacher)
):
    """Set a leaving time by hand.

    Attendance only counts once the student scans out, which is deliberate, but
    a student who genuinely attended and simply forgot would otherwise lose the
    whole block with no way back. The correction is recorded as a teacher
    override rather than disguised as a scan.
    """
    with get_db() as conn:
        row = conn.execute(
            """SELECT a.id, a.session_id FROM attendance a
               JOIN students s ON s.id = a.student_id
               WHERE a.id = ? AND s.owner_id = ?""",
            (attendance_id, user["id"]),
        ).fetchone()
        if row is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Attendance record not found")
        if body.exit_at is not None:
            try:
                datetime.strptime(body.exit_at.strip(), "%H:%M")
            except ValueError:
                raise HTTPException(
                    status.HTTP_422_UNPROCESSABLE_ENTITY, "Leaving time must be HH:MM"
                )
            conn.execute(
                """UPDATE attendance
                   SET exit_at = ?, exit_source = 'teacher', override_note = ?
                   WHERE id = ?""",
                (body.exit_at.strip(), body.note.strip()[:300], attendance_id),
            )
        updated = conn.execute("SELECT * FROM attendance WHERE id = ?", (attendance_id,)).fetchone()
    return dict(updated)
