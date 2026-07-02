from fastapi import APIRouter, Depends, File, HTTPException, Request, UploadFile, status
from pydantic import BaseModel

from .. import config
from ..db import get_db
from ..face_engine import EnrollmentError
from ..security import require_teacher

router = APIRouter(prefix="/students", tags=["students"])


class StudentIn(BaseModel):
    roll_no: str
    name: str
    class_name: str = ""


def _owned_student(conn, student_id: int, user: dict):
    student = conn.execute("SELECT * FROM students WHERE id = ?", (student_id,)).fetchone()
    if student is None or student["owner_id"] != user["id"]:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Student not found")
    return student


@router.post("", status_code=status.HTTP_201_CREATED)
def create_student(body: StudentIn, user: dict = Depends(require_teacher)):
    roll_no = body.roll_no.strip()
    name = body.name.strip()
    if not roll_no or not name:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Roll number and name are required")
    with get_db() as conn:
        existing = conn.execute(
            "SELECT id FROM students WHERE owner_id = ? AND roll_no = ?", (user["id"], roll_no)
        ).fetchone()
        if existing:
            raise HTTPException(status.HTTP_409_CONFLICT, "You already have a student with this roll number")
        cur = conn.execute(
            "INSERT INTO students (owner_id, roll_no, name, class_name) VALUES (?, ?, ?, ?)",
            (user["id"], roll_no, name, body.class_name.strip()),
        )
        student_id = cur.lastrowid
    return {"id": student_id, "roll_no": roll_no, "name": name, "class_name": body.class_name.strip()}


@router.get("")
def list_students(user: dict = Depends(require_teacher)):
    with get_db() as conn:
        rows = conn.execute(
            """SELECT s.*, COUNT(e.id) AS enrolled_images
               FROM students s LEFT JOIN embeddings e ON e.student_id = s.id
               WHERE s.owner_id = ?
               GROUP BY s.id ORDER BY s.roll_no""",
            (user["id"],),
        ).fetchall()
    return [dict(r) for r in rows]


@router.delete("/{student_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_student(student_id: int, request: Request, user: dict = Depends(require_teacher)):
    with get_db() as conn:
        _owned_student(conn, student_id, user)
        conn.execute("DELETE FROM students WHERE id = ?", (student_id,))
    request.app.state.engine.reload_index()


@router.post("/{student_id}/enroll")
async def enroll_student(
    student_id: int,
    request: Request,
    images: list[UploadFile] = File(...),
    user: dict = Depends(require_teacher),
):
    if not (config.MIN_ENROLL_IMAGES <= len(images) <= config.MAX_ENROLL_IMAGES):
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            f"Upload between {config.MIN_ENROLL_IMAGES} and {config.MAX_ENROLL_IMAGES} images",
        )
    with get_db() as conn:
        _owned_student(conn, student_id, user)

    engine = request.app.state.engine
    accepted, rejected = [], []
    for image in images:
        data = await image.read()
        try:
            accepted.append(engine.embed_for_enrollment(data))
        except EnrollmentError as exc:
            rejected.append({"filename": image.filename, "reason": str(exc)})

    if len(accepted) < config.MIN_ENROLL_IMAGES:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            {"message": f"Only {len(accepted)} usable images, need {config.MIN_ENROLL_IMAGES}", "rejected": rejected},
        )

    with get_db() as conn:
        conn.execute("DELETE FROM embeddings WHERE student_id = ?", (student_id,))
        conn.executemany(
            "INSERT INTO embeddings (student_id, vector) VALUES (?, ?)",
            [(student_id, emb.tobytes()) for emb in accepted],
        )
    engine.reload_index()
    return {"student_id": student_id, "enrolled_images": len(accepted), "rejected": rejected}
