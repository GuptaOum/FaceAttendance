from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel

from ..db import get_db
from ..security import require_teacher

router = APIRouter(prefix="/sessions", tags=["sessions"])


class SessionIn(BaseModel):
    title: str
    group_name: str = ""
    date: str
    start_time: str
    end_time: str


def _validate(body: SessionIn):
    title = body.title.strip()
    if not title:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Title is required")
    try:
        datetime.strptime(body.date, "%Y-%m-%d")
        start = datetime.strptime(body.start_time, "%H:%M")
        end = datetime.strptime(body.end_time, "%H:%M")
    except ValueError:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Invalid date or time format")
    if end <= start:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "End time must be after start time")
    return title


@router.post("", status_code=status.HTTP_201_CREATED)
def create_session(body: SessionIn, user: dict = Depends(require_teacher)):
    title = _validate(body)
    with get_db() as conn:
        cur = conn.execute(
            """INSERT INTO sessions (owner_id, title, group_name, date, start_time, end_time)
               VALUES (?, ?, ?, ?, ?, ?)""",
            (user["id"], title, body.group_name.strip(), body.date, body.start_time, body.end_time),
        )
        session_id = cur.lastrowid
    return {
        "id": session_id, "title": title, "group_name": body.group_name.strip(),
        "date": body.date, "start_time": body.start_time, "end_time": body.end_time,
    }


@router.get("")
def list_sessions(user: dict = Depends(require_teacher)):
    with get_db() as conn:
        rows = conn.execute(
            "SELECT * FROM sessions WHERE owner_id = ? ORDER BY date DESC, start_time",
            (user["id"],),
        ).fetchall()
    return [dict(r) for r in rows]


@router.delete("/{session_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_session(session_id: int, user: dict = Depends(require_teacher)):
    with get_db() as conn:
        cur = conn.execute(
            "DELETE FROM sessions WHERE id = ? AND owner_id = ?", (session_id, user["id"])
        )
        if cur.rowcount == 0:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Session not found")
