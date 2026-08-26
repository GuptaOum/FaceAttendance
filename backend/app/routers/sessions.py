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
    spot_check_enabled: bool = False


class BlockIn(BaseModel):
    """One scan-block of the day, e.g. 10:00-13:00 covering three periods."""
    title: str
    start_time: str
    end_time: str
    entry_until: str | None = None
    exit_from: str | None = None
    exit_until: str | None = None
    periods: list[PeriodIn] = Field(default_factory=list)
    spot_check_enabled: bool = False


class DayIn(BaseModel):
    """One weekday's own blocks. 0 = Monday .. 6 = Sunday."""
    weekday: int = Field(ge=0, le=6)
    blocks: list[BlockIn] = Field(default_factory=list)


class TimetableIn(BaseModel):
    """A weekly timetable scheduled ahead of time.

    Real timetables differ by day - a Saturday half day may run one period in
    the afternoon where a Monday runs three - so each weekday carries its own
    blocks via `days`. The older `weekdays` + `blocks` form is still accepted
    and simply applies one set of blocks to every listed day.
    """
    group_name: str = ""
    start_date: str
    weeks: int = Field(default=1, ge=1, le=26)
    days: list[DayIn] = Field(default_factory=list)
    weekdays: list[int] = Field(default_factory=list)
    blocks: list[BlockIn] = Field(default_factory=list)
    replace_existing: bool = False

    def per_day(self) -> list[DayIn]:
        """Normalise both request shapes into one blocks-per-weekday list."""
        if self.days:
            return [d for d in self.days if d.blocks]
        return [DayIn(weekday=w, blocks=self.blocks) for w in sorted(set(self.weekdays))]


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


def _validate_periods(periods: list, block_start: str, block_end: str) -> list:
    """Check periods before storing them.

    A period outside its block can never be earned, and overlapping periods
    double-count the same minutes. Both silently corrupt every attendance
    percentage, so they are rejected rather than accepted quietly.
    """
    ordered = sorted(periods, key=lambda p: p.start_time)
    previous_end = None
    for seq, p in enumerate(ordered, start=1):
        subject = p.subject.strip() or f"Period {seq}"
        _parse_time(p.start_time, "period start")
        _parse_time(p.end_time, "period end")
        if p.end_time <= p.start_time:
            raise HTTPException(
                status.HTTP_422_UNPROCESSABLE_ENTITY,
                f"{subject}: end time must be after start time",
            )
        if p.start_time < block_start or p.end_time > block_end:
            raise HTTPException(
                status.HTTP_422_UNPROCESSABLE_ENTITY,
                f"{subject} ({p.start_time}-{p.end_time}) is outside the block "
                f"{block_start}-{block_end}. Students could never attend it.",
            )
        if previous_end is not None and p.start_time < previous_end:
            raise HTTPException(
                status.HTTP_422_UNPROCESSABLE_ENTITY,
                f"{subject} starts at {p.start_time}, before the previous period ends "
                f"at {previous_end}. Periods must not overlap.",
            )
        previous_end = p.end_time
    return ordered


def _insert_periods(conn, session_id: int, periods: list, block_start: str, block_end: str) -> int:
    """Store the periods inside a block, ordered by start time."""
    ordered = _validate_periods(periods, block_start, block_end)
    for seq, p in enumerate(ordered, start=1):
        conn.execute(
            "INSERT INTO periods (session_id, seq, subject, start_time, end_time) VALUES (?, ?, ?, ?, ?)",
            (session_id, seq, p.subject.strip() or f"Period {seq}", p.start_time, p.end_time),
        )
    return len(ordered)


@router.post("", status_code=status.HTTP_201_CREATED)
def create_session(body: SessionIn, user: dict = Depends(require_teacher)):
    title, entry_until, exit_from, exit_until = _validate(body)
    with get_db() as conn:
        cur = conn.execute(
            """INSERT INTO sessions
               (owner_id, title, group_name, date, start_time, end_time, entry_until, exit_from, exit_until, spot_check_enabled)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (user["id"], title, body.group_name.strip(), body.date,
             body.start_time, body.end_time, entry_until, exit_from, exit_until,
             1 if body.spot_check_enabled else 0),
        )
        session_id = cur.lastrowid
        _insert_periods(conn, session_id, body.periods, body.start_time, body.end_time)
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
    schedule = body.per_day()
    if not schedule:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY, "Add at least one day with a block"
        )

    # Validate every block of every day up front, so one bad block cannot leave
    # a half-built week behind.
    prepared: dict[int, list] = {}
    for day in schedule:
        for b in day.blocks:
            checked = _validate(SessionIn(
                title=b.title, group_name=body.group_name, date=body.start_date,
                start_time=b.start_time, end_time=b.end_time, entry_until=b.entry_until,
                exit_from=b.exit_from, exit_until=b.exit_until,
            ))
            _validate_periods(b.periods, b.start_time, b.end_time)
            prepared.setdefault(day.weekday, []).append((b, checked))

    created, skipped = [], []
    with get_db() as conn:
        for week in range(body.weeks):
            for offset in range(7):
                day = start + timedelta(days=week * 7 + offset)
                if day.weekday() not in prepared or day < start:
                    continue
                day_str = day.isoformat()
                # Each weekday runs its own blocks, so a Saturday half day can
                # carry fewer periods than a Monday.
                for b, (title, entry_until, exit_from, exit_until) in prepared[day.weekday()]:
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
                            entry_until, exit_from, exit_until, spot_check_enabled)
                           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                        (user["id"], title, body.group_name.strip(), day_str,
                         b.start_time, b.end_time, entry_until, exit_from, exit_until,
                         1 if b.spot_check_enabled else 0),
                    )
                    n = _insert_periods(conn, cur.lastrowid, b.periods, b.start_time, b.end_time)
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


class SpotCheckIn(BaseModel):
    """Students the teacher could not see in the room right now."""
    absent_student_ids: list[int] = Field(default_factory=list)
    checked_at: str | None = None


@router.get("/{session_id}/present")
def who_is_present(session_id: int, user: dict = Depends(require_teacher)):
    """Students currently marked present in this block, for a roll call."""
    with get_db() as conn:
        sess = conn.execute(
            "SELECT * FROM sessions WHERE id = ? AND owner_id = ?", (session_id, user["id"])
        ).fetchone()
        if sess is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Session not found")
        rows = conn.execute(
            """SELECT s.id, s.roll_no, s.name, a.marked_at, a.exit_at
               FROM attendance a JOIN students s ON s.id = a.student_id
               WHERE a.session_id = ? ORDER BY s.roll_no""",
            (session_id,),
        ).fetchall()
    return {"session": dict(sess), "present": [dict(r) for r in rows]}


@router.post("/{session_id}/spot-check", status_code=status.HTTP_201_CREATED)
def run_spot_check(session_id: int, body: SpotCheckIn, user: dict = Depends(require_teacher)):
    """Record an optional mid-block roll call.

    Entirely the teacher's choice - nothing schedules this. Students marked
    missing have their presence truncated at this moment and forfeit the rest
    of the block. Anyone who had not arrived yet, or had already scanned out,
    is untouched: they are not claiming this time in the first place.
    """
    checked_at = (body.checked_at or datetime.now().strftime(TIME_FMT)).strip()
    _parse_time(checked_at, "spot check")
    with get_db() as conn:
        sess = conn.execute(
            "SELECT * FROM sessions WHERE id = ? AND owner_id = ?", (session_id, user["id"])
        ).fetchone()
        if sess is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Session not found")
        if not sess["spot_check_enabled"]:
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                "Spot checks are turned off for this block. Turn them on first.",
            )

        eligible = {
            r["student_id"]: r
            for r in conn.execute(
                """SELECT a.student_id, a.marked_at, a.exit_at
                   FROM attendance a WHERE a.session_id = ?""",
                (session_id,),
            ).fetchall()
        }
        cur = conn.execute(
            "INSERT INTO spot_checks (session_id, checked_at, created_by) VALUES (?, ?, ?)",
            (session_id, checked_at, user["id"]),
        )
        check_id = cur.lastrowid

        applied, exempt = [], []
        for sid in set(body.absent_student_ids):
            row = eligible.get(sid)
            if row is None:
                exempt.append({"student_id": sid, "reason": "not marked present in this block"})
                continue
            arrived = (row["marked_at"] or "")[-8:][:5]
            if arrived and arrived > checked_at:
                exempt.append({"student_id": sid, "reason": f"had not arrived yet (came {arrived})"})
                continue
            left = (row["exit_at"] or "")[-8:][:5]
            if left and left <= checked_at:
                exempt.append({"student_id": sid, "reason": f"already scanned out at {left}"})
                continue
            conn.execute(
                "INSERT OR IGNORE INTO spot_check_absences (spot_check_id, student_id) VALUES (?, ?)",
                (check_id, sid),
            )
            applied.append(sid)
    return {
        "spot_check_id": check_id, "checked_at": checked_at,
        "marked_absent": len(applied), "exempt": exempt,
    }


@router.get("/{session_id}/spot-checks")
def list_spot_checks(session_id: int, user: dict = Depends(require_teacher)):
    with get_db() as conn:
        sess = conn.execute(
            "SELECT id FROM sessions WHERE id = ? AND owner_id = ?", (session_id, user["id"])
        ).fetchone()
        if sess is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Session not found")
        rows = conn.execute(
            """SELECT c.id, c.checked_at, c.created_ts, COUNT(a.student_id) AS absent_count
               FROM spot_checks c LEFT JOIN spot_check_absences a ON a.spot_check_id = c.id
               WHERE c.session_id = ? GROUP BY c.id ORDER BY c.checked_at""",
            (session_id,),
        ).fetchall()
    return [dict(r) for r in rows]


class SessionToggle(BaseModel):
    spot_check_enabled: bool


@router.patch("/{session_id}")
def update_session(session_id: int, body: SessionToggle, user: dict = Depends(require_teacher)):
    """Turn the optional roll call on or off for one block."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT id FROM sessions WHERE id = ? AND owner_id = ?", (session_id, user["id"])
        ).fetchone()
        if row is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Session not found")
        conn.execute(
            "UPDATE sessions SET spot_check_enabled = ? WHERE id = ?",
            (1 if body.spot_check_enabled else 0, session_id),
        )
    return {"id": session_id, "spot_check_enabled": body.spot_check_enabled}
