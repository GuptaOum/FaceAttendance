from datetime import date as date_cls
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from ..db import get_db
from ..security import require_teacher

router = APIRouter(prefix="/sessions", tags=["sessions"])

TIME_FMT = "%H:%M"
WEEKDAY_NAMES = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]


class PeriodIn(BaseModel):
    subject: str
    start_time: str
    end_time: str


class SessionIn(BaseModel):
    title: str
    group_name: str = ""
    date: str
    start_time: str
    end_time: str
    entry_until: str | None = None
    exit_from: str | None = None
    exit_until: str | None = None
    periods: list[PeriodIn] = Field(default_factory=list)


class BlockIn(BaseModel):
    """One scan-block of the day, e.g. 10:00-13:00 covering three periods."""
    title: str
    start_time: str
    end_time: str
    entry_until: str | None = None
    exit_from: str | None = None
    exit_until: str | None = None
    periods: list[PeriodIn] = Field(default_factory=list)


class TimetableIn(BaseModel):
    """A weekly timetable scheduled ahead of time.

    Blocks repeat on the chosen weekdays for `weeks` weeks starting from
    `start_date`, so a teacher sets the week up once instead of creating each
    day by hand.
    """
    group_name: str = ""
    start_date: str
    weeks: int = Field(default=1, ge=1, le=26)
    weekdays: list[int] = Field(default_factory=lambda: [0, 1, 2, 3, 4])
    blocks: list[BlockIn]
    replace_existing: bool = False


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


def _insert_periods(conn, session_id: int, periods: list) -> int:
    """Store the periods inside a block, ordered by start time."""
    ordered = sorted(periods, key=lambda p: p.start_time)
    for seq, p in enumerate(ordered, start=1):
        subject = p.subject.strip() or f"Period {seq}"
        _parse_time(p.start_time, "period start")
        _parse_time(p.end_time, "period end")
        if p.end_time <= p.start_time:
            raise HTTPException(
                status.HTTP_422_UNPROCESSABLE_ENTITY,
                f"{subject}: end time must be after start time",
            )
        conn.execute(
            "INSERT INTO periods (session_id, seq, subject, start_time, end_time) VALUES (?, ?, ?, ?, ?)",
            (session_id, seq, subject, p.start_time, p.end_time),
        )
    return len(ordered)


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
        _insert_periods(conn, session_id, body.periods)
        row = conn.execute("SELECT * FROM sessions WHERE id = ?", (session_id,)).fetchone()
        periods = conn.execute(
            "SELECT seq, subject, start_time, end_time FROM periods WHERE session_id = ? ORDER BY seq",
            (session_id,),
        ).fetchall()
    return {**dict(row), "periods": [dict(p) for p in periods]}


@router.post("/timetable", status_code=status.HTTP_201_CREATED)
def create_timetable(body: TimetableIn, user: dict = Depends(require_teacher)):
    """Schedule a repeating weekly timetable in advance.

    Each block becomes one session per selected weekday, with its periods
    attached. Students scan at block entry and block exit only.
    """
    try:
        start = datetime.strptime(body.start_date, "%Y-%m-%d").date()
    except ValueError:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Invalid start date")
    if not body.blocks:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Add at least one block")
    weekdays = sorted({d for d in body.weekdays if 0 <= d <= 6})
    if not weekdays:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Select at least one weekday")

    # Validate every block up front so a bad block cannot leave a half-built week.
    prepared = []
    for b in body.blocks:
        checked = _validate(SessionIn(
            title=b.title, group_name=body.group_name, date=body.start_date,
            start_time=b.start_time, end_time=b.end_time, entry_until=b.entry_until,
            exit_from=b.exit_from, exit_until=b.exit_until,
        ))
        prepared.append((b, checked))

    created, skipped = [], []
    with get_db() as conn:
        for week in range(body.weeks):
            for offset in range(7):
                day = start + timedelta(days=week * 7 + offset)
                if day.weekday() not in weekdays or day < start:
                    continue
                day_str = day.isoformat()
                for b, (title, entry_until, exit_from, exit_until) in prepared:
                    existing = conn.execute(
                        """SELECT id FROM sessions
                           WHERE owner_id = ? AND date = ? AND title = ? AND start_time = ?""",
                        (user["id"], day_str, title, b.start_time),
                    ).fetchone()
                    if existing:
                        if not body.replace_existing:
                            skipped.append({"date": day_str, "title": title,
                                            "reason": "already scheduled"})
                            continue
                        conn.execute("DELETE FROM sessions WHERE id = ?", (existing["id"],))
                    cur = conn.execute(
                        """INSERT INTO sessions
                           (owner_id, title, group_name, date, start_time, end_time,
                            entry_until, exit_from, exit_until)
                           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                        (user["id"], title, body.group_name.strip(), day_str,
                         b.start_time, b.end_time, entry_until, exit_from, exit_until),
                    )
                    n = _insert_periods(conn, cur.lastrowid, b.periods)
                    created.append({"date": day_str, "weekday": WEEKDAY_NAMES[day.weekday()],
                                    "title": title, "periods": n})
    return {
        "created": len(created), "skipped": len(skipped),
        "sessions": created, "skipped_detail": skipped,
    }


@router.get("")
def list_sessions(user: dict = Depends(require_teacher)):
    with get_db() as conn:
        rows = conn.execute(
            "SELECT * FROM sessions WHERE owner_id = ? ORDER BY date DESC, start_time",
            (user["id"],),
        ).fetchall()
        by_session: dict[int, list] = {}
        for p in conn.execute(
            """SELECT p.session_id, p.seq, p.subject, p.start_time, p.end_time
               FROM periods p JOIN sessions s ON s.id = p.session_id
               WHERE s.owner_id = ? ORDER BY p.session_id, p.seq""",
            (user["id"],),
        ).fetchall():
            by_session.setdefault(p["session_id"], []).append(
                {k: p[k] for k in ("seq", "subject", "start_time", "end_time")}
            )
    return [{**dict(r), "periods": by_session.get(r["id"], [])} for r in rows]


@router.delete("/{session_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_session(session_id: int, user: dict = Depends(require_teacher)):
    with get_db() as conn:
        cur = conn.execute(
            "DELETE FROM sessions WHERE id = ? AND owner_id = ?", (session_id, user["id"])
        )
        if cur.rowcount == 0:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Session not found")
