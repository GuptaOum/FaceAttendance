from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel

from ..db import get_db
from ..security import require_teacher

router = APIRouter(prefix="/sessions", tags=["sessions"])

TIME_FMT = "%H:%M"


class SessionIn(BaseModel):
    title: str
    group_name: str = ""
    date: str
    start_time: str
    end_time: str
    entry_until: str | None = None
    exit_from: str | None = None
    exit_until: str | None = None


def _parse_time(value: str, label: str) -> datetime:
    try:
        return datetime.strptime(value, TIME_FMT)
    except ValueError:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, f"Invalid {label} time (use HH:MM)")


def _shift(t: datetime, minutes: int) -> str:
    shifted = t + timedelta(minutes=minutes)
    if shifted.day != t.day:
        shifted = t.replace(hour=23, minute=59) if minutes > 0 else t.replace(hour=0, minute=0)
    return shifted.strftime(TIME_FMT)


def _validate(body: SessionIn):
    title = body.title.strip()
    if not title:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Title is required")
    try:
        datetime.strptime(body.date, "%Y-%m-%d")
    except ValueError:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Invalid date format")

    start = _parse_time(body.start_time, "start")
    end = _parse_time(body.end_time, "end")
    if end <= start:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "End time must be after start time")

    entry_until = body.entry_until or _shift(start, 15)
    exit_from = body.exit_from or _shift(end, -10)
    exit_until = body.exit_until or _shift(end, 15)

    e_until = _parse_time(entry_until, "entry-until")
    x_from = _parse_time(exit_from, "exit-from")
    x_until = _parse_time(exit_until, "exit-until")

    if e_until <= start:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Entry window must end after class start")
    if x_from >= x_until:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Exit window must open before it closes")
    if x_from <= e_until:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "Exit window must open after the entry window closes",
        )
    return title, entry_until, exit_from, exit_until


@router.post("", status_code=status.HTTP_201_CREATED)
def create_session(body: SessionIn, user: dict = Depends(require_teacher)):
    title, entry_until, exit_from, exit_until = _validate(body)
    with get_db() as conn:
        cur = conn.execute(
            """INSERT INTO sessions
               (owner_id, title, group_name, date, start_time, end_time, entry_until, exit_from, exit_until)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (user["id"], title, body.group_name.strip(), body.date,
             body.start_time, body.end_time, entry_until, exit_from, exit_until),
        )
        session_id = cur.lastrowid
        row = conn.execute("SELECT * FROM sessions WHERE id = ?", (session_id,)).fetchone()
    return dict(row)


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
