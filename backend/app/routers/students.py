from fastapi import APIRouter, Depends, File, HTTPException, Request, UploadFile, status
from pydantic import BaseModel

from .. import config
from ..db import get_db
from ..face_engine import EnrollmentError
from ..security import hash_password, require_admin

router = APIRouter(prefix="/students", tags=["students"])


class StudentIn(BaseModel):
    roll_no: str
    name: str
    class_name: str = ""
    password: str | None = None


@router.post("", status_code=status.HTTP_201_CREATED)
def create_student(body: StudentIn, _: dict = Depends(require_admin)):
    with get_db() as conn:
        existing = conn.execute("SELECT id FROM students WHERE roll_no = ?", (body.roll_no,)).fetchone()
        if existing:
            raise HTTPException(status.HTTP_409_CONFLICT, "Roll number already registered")
        cur = conn.execute(
            "INSERT INTO students (roll_no, name, class_name) VALUES (?, ?, ?)",
            (body.roll_no, body.name, body.class_name),
        )
        student_id = cur.lastrowid
        password = body.password or body.roll_no
        conn.execute(
            "INSERT INTO users (username, password_hash, role, student_id) VALUES (?, ?, 'student', ?)",
            (body.roll_no, hash_password(password), student_id),
        )
    return {"id": student_id, "roll_no": body.roll_no, "name": body.name, "class_name": body.class_name}


@router.get("")
def list_students(_: dict = Depends(require_admin)):
    with get_db() as conn:
        rows = conn.execute(
            """SELECT s.*, COUNT(e.id) AS enrolled_images
               FROM students s LEFT JOIN embeddings e ON e.student_id = s.id
               GROUP BY s.id ORDER BY s.roll_no"""
        ).fetchall()
    return [dict(r) for r in rows]


@router.delete("/{student_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_student(student_id: int, request: Request, _: dict = Depends(require_admin)):
    with get_db() as conn:
        cur = conn.execute("DELETE FROM students WHERE id = ?", (student_id,))
        if cur.rowcount == 0:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Student not found")
    request.app.state.engine.reload_index()


@router.post("/{student_id}/enroll")
async def enroll_student(
    student_id: int,
    request: Request,
    images: list[UploadFile] = File(...),
    _: dict = Depends(require_admin),
):
    if not (config.MIN_ENROLL_IMAGES <= len(images) <= config.MAX_ENROLL_IMAGES):
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            f"Upload between {config.MIN_ENROLL_IMAGES} and {config.MAX_ENROLL_IMAGES} images",
        )
    with get_db() as conn:
        student = conn.execute("SELECT id FROM students WHERE id = ?", (student_id,)).fetchone()
    if student is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Student not found")

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
