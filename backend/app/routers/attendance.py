from datetime import date

from fastapi import APIRouter, Depends, File, HTTPException, Request, UploadFile, status

from ..db import get_db
from ..security import get_current_user, require_admin

router = APIRouter(prefix="/attendance", tags=["attendance"])


@router.post("/recognize")
async def recognize(request: Request, image: UploadFile = File(...), _: dict = Depends(require_admin)):
    engine = request.app.state.engine
    embedding = engine.embed_largest_face(await image.read())
    if embedding is None:
        return {"matched": False, "reason": "no_face"}

    result = engine.match(embedding)
    if result is None:
        return {"matched": False, "reason": "unknown_face"}

    student_id, confidence = result
    today = date.today().isoformat()
    with get_db() as conn:
        student = conn.execute("SELECT * FROM students WHERE id = ?", (student_id,)).fetchone()
        already = conn.execute(
            "SELECT marked_at FROM attendance WHERE student_id = ? AND date = ?", (student_id, today)
        ).fetchone()
        if already is None:
            conn.execute(
                "INSERT INTO attendance (student_id, date, confidence) VALUES (?, ?, ?)",
                (student_id, today, confidence),
            )
    return {
        "matched": True,
        "student": {"id": student["id"], "roll_no": student["roll_no"], "name": student["name"]},
        "confidence": round(confidence, 3),
        "already_marked": already is not None,
        "marked_at": already["marked_at"] if already else None,
    }


@router.get("")
def attendance_report(day: str | None = None, _: dict = Depends(require_admin)):
    target = day or date.today().isoformat()
    with get_db() as conn:
        present = conn.execute(
            """SELECT s.id, s.roll_no, s.name, s.class_name, a.marked_at, a.confidence
               FROM attendance a JOIN students s ON s.id = a.student_id
               WHERE a.date = ? ORDER BY a.marked_at""",
            (target,),
        ).fetchall()
        absent = conn.execute(
            """SELECT s.id, s.roll_no, s.name, s.class_name FROM students s
               WHERE s.id NOT IN (SELECT student_id FROM attendance WHERE date = ?)
               ORDER BY s.roll_no""",
            (target,),
        ).fetchall()
    return {"date": target, "present": [dict(r) for r in present], "absent": [dict(r) for r in absent]}


@router.get("/me")
def my_attendance(user: dict = Depends(get_current_user)):
    if user["student_id"] is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Not a student account")
    with get_db() as conn:
        rows = conn.execute(
            "SELECT date, marked_at, confidence FROM attendance WHERE student_id = ? ORDER BY date DESC LIMIT 90",
            (user["student_id"],),
        ).fetchall()
    return [dict(r) for r in rows]
