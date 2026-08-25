"""Derive per-period attendance from a single entry/exit scan pair.

Students scan once when they arrive at a block and once when they leave. Every
period inside that block is then judged against the interval those two scans
define, so back-to-back classes need no extra queueing.

Nothing here invents attendance. A period is only credited when the student was
actually inside the room for enough of it, and a block with no exit scan is
reported as unverified rather than silently counted as present.
"""

from datetime import datetime

from . import config

TIME_FMT = "%H:%M"

# Status values. Presence is only ever claimed for a completed entry+exit pair:
# an entry scan alone proves arrival, not that the student stayed, so it is
# never counted as attendance.
PRESENT = "present"          # covered by a completed entry+exit interval
PENDING_EXIT = "pending_exit"  # entry seen, no exit scan yet - NOT counted present
ABSENT = "absent"            # not covered by the interval


def _to_minutes(value: str) -> int | None:
    """'HH:MM' or 'YYYY-MM-DD HH:MM:SS' -> minutes since midnight."""
    if not value:
        return None
    text = value.strip()
    if " " in text:
        text = text.split(" ", 1)[1]
    text = text[:5]
    try:
        t = datetime.strptime(text, TIME_FMT)
    except ValueError:
        return None
    return t.hour * 60 + t.minute


def _overlap(a_start: int, a_end: int, b_start: int, b_end: int) -> int:
    return max(0, min(a_end, b_end) - max(a_start, b_start))


def period_status(
    period: dict, entry_at: str | None, exit_at: str | None, block_end: str
) -> tuple[str, float]:
    """Status of one period given the student's presence interval.

    Returns (status, covered_fraction). A period counts as attended when the
    student was present for at least MIN_PERIOD_COVERAGE of it - arriving with
    only the last two minutes of a period left should not earn credit for it.
    """
    p_start = _to_minutes(period["start_time"])
    p_end = _to_minutes(period["end_time"])
    if p_start is None or p_end is None or p_end <= p_start:
        return ABSENT, 0.0

    entry = _to_minutes(entry_at) if entry_at else None
    if entry is None:
        return ABSENT, 0.0

    # No exit scan: we only know they were here from `entry` onwards. Treat the
    # block end as the optimistic bound but flag the result as unverified.
    exit_known = exit_at is not None
    leave = _to_minutes(exit_at) if exit_known else _to_minutes(block_end)
    if leave is None or leave <= entry:
        leave = p_end if not exit_known else entry

    covered = _overlap(entry, leave, p_start, p_end) / (p_end - p_start)
    if covered < config.MIN_PERIOD_COVERAGE:
        return ABSENT, round(covered, 3)
    # Without an exit scan we only know the student arrived. That is reported as
    # pending, never as present - leaving without scanning out must not earn a
    # full block of attendance.
    return (PRESENT if exit_known else PENDING_EXIT), round(covered, 3)


def summarise(periods: list, entry_at: str | None, exit_at: str | None, block_end: str) -> dict:
    """Per-period breakdown plus counts, e.g. '2 of 3 periods'."""
    rows = []
    for p in periods:
        status, covered = period_status(dict(p), entry_at, exit_at, block_end)
        rows.append({
            "seq": p["seq"],
            "subject": p["subject"],
            "start_time": p["start_time"],
            "end_time": p["end_time"],
            "status": status,
            "covered": covered,
        })
    # Only completed entry+exit pairs count. Periods still waiting on an exit
    # scan are reported separately so the teacher can see them, but they do not
    # inflate the attended figure.
    attended = sum(1 for r in rows if r["status"] == PRESENT)
    pending = sum(1 for r in rows if r["status"] == PENDING_EXIT)
    return {
        "periods": rows,
        "attended": attended,
        "pending": pending,
        "total": len(rows),
        "label": f"{attended} of {len(rows)} periods" if rows else "",
        "awaiting_exit": pending > 0,
    }
