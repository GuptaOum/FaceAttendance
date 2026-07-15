from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from ..db import get_db
from ..security import get_current_user, require_teacher

router = APIRouter(prefix="/face-requests", tags=["face-requests"])

REQUEST_TYPES = ("reenroll", "issue")
RESOLUTIONS = ("resolved", "rejected")


class FaceRequestIn(BaseModel):
    request_type: str = "reenroll"
    message: str = Field(default="", max_length=500)


class FaceRequestResolve(BaseModel):
    status: str
    teacher_notes: str = Field(default="", max_length=500)


def _student_for_user(conn, user: dict):
    """Resolve the student row for a logged-in student.

    Mirrors the users.username = students.roll_no convention that /attendance/me
    already relies on; there is no direct FK from users to students.
    """
    if user["role"] != "student":
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Student access required")
    student = conn.execute(
        "SELECT * FROM students WHERE roll_no = ?", (user["username"],)
    ).fetchone()
    if student is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "No student record for this login")
    return student


@router.post("", status_code=status.HTTP_201_CREATED)
def create_request(body: FaceRequestIn, user: dict = Depends(get_current_user)):
    if body.request_type not in REQUEST_TYPES:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            f"request_type must be one of {', '.join(REQUEST_TYPES)}",
        )
    with get_db() as conn:
        student = _student_for_user(conn, user)
        open_req = conn.execute(
            "SELECT id FROM face_requests WHERE student_id = ? AND status = 'open'",
            (student["id"],),
        ).fetchone()
        if open_req:
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                "You already have a pending request, please wait for your teacher to review it",
            )
        cur = conn.execute(
            "INSERT INTO face_requests (student_id, request_type, message) VALUES (?, ?, ?)",
            (student["id"], body.request_type, body.message.strip()),
        )
        request_id = cur.lastrowid
    return {"id": request_id, "status": "open"}


@router.get("/me")
def my_requests(user: dict = Depends(get_current_user)):
    with get_db() as conn:
        student = _student_for_user(conn, user)
        rows = conn.execute(
            """SELECT id, request_type, message, status, teacher_notes, created_at, resolved_at
               FROM face_requests WHERE student_id = ? ORDER BY created_at DESC LIMIT 50""",
            (student["id"],),
        ).fetchall()
    return [dict(r) for r in rows]


@router.get("")
def list_requests(status_filter: str = "open", user: dict = Depends(require_teacher)):
    """Requests raised by students this teacher owns. status_filter='all' returns every state."""
    query = """SELECT f.id, f.student_id, f.request_type, f.message, f.status, f.teacher_notes,
                      f.created_at, f.resolved_at, s.roll_no, s.name, s.class_name
               FROM face_requests f JOIN students s ON s.id = f.student_id
               WHERE s.owner_id = ?"""
    params: list = [user["id"]]
    if status_filter != "all":
        query += " AND f.status = ?"
        params.append(status_filter)
    query += " ORDER BY f.created_at DESC LIMIT 200"
    with get_db() as conn:
        rows = conn.execute(query, params).fetchall()
    return [dict(r) for r in rows]


@router.patch("/{request_id}")
def resolve_request(
    request_id: int, body: FaceRequestResolve, user: dict = Depends(require_teacher)
):
    if body.status not in RESOLUTIONS:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            f"status must be one of {', '.join(RESOLUTIONS)}",
        )
    with get_db() as conn:
        row = conn.execute(
            """SELECT f.id FROM face_requests f JOIN students s ON s.id = f.student_id
               WHERE f.id = ? AND s.owner_id = ?""",
            (request_id, user["id"]),
        ).fetchone()
        if row is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Request not found")
        conn.execute(
            """UPDATE face_requests
               SET status = ?, teacher_notes = ?, resolved_at = datetime('now', 'localtime')
               WHERE id = ?""",
            (body.status, body.teacher_notes.strip(), request_id),
        )
    return {"id": request_id, "status": body.status}
