import sqlite3
from contextlib import contextmanager

from . import config

SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('admin', 'teacher', 'student')),
    must_change_password INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS students (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    owner_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    roll_no TEXT NOT NULL,
    name TEXT NOT NULL,
    class_name TEXT NOT NULL DEFAULT '',
    parent_phone TEXT NOT NULL DEFAULT '',
    -- The student's own read-only login. Nullable so a student can exist
    -- before (or without) a login being issued.
    user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(owner_id, roll_no)
);

CREATE TABLE IF NOT EXISTS embeddings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    vector BLOB NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    owner_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    group_name TEXT NOT NULL DEFAULT '',
    date TEXT NOT NULL,
    start_time TEXT NOT NULL,
    end_time TEXT NOT NULL,
    entry_until TEXT NOT NULL DEFAULT '',
    exit_from TEXT NOT NULL DEFAULT '',
    exit_until TEXT NOT NULL DEFAULT '',
    -- Optional per-block roll call. Off by default: the teacher opts in.
    spot_check_enabled INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Periods inside a block (session). Students scan once at block entry and once
-- at block exit; per-period presence is derived from that interval, so there is
-- no scanning between back-to-back classes.
CREATE TABLE IF NOT EXISTS periods (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    seq INTEGER NOT NULL,
    subject TEXT NOT NULL,
    start_time TEXT NOT NULL,
    end_time TEXT NOT NULL,
    UNIQUE(session_id, seq)
);

-- Optional mid-block roll call. Entirely the teacher's choice: they tap once,
-- glance at the room and tick anyone missing. No student queues at the kiosk,
-- so it costs seconds instead of disrupting the lesson.
CREATE TABLE IF NOT EXISTS spot_checks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    checked_at TEXT NOT NULL,
    created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
    created_ts TEXT NOT NULL DEFAULT (datetime('now', 'localtime'))
);

-- Students the teacher marked missing at that moment. Their presence interval
-- is truncated there, so they forfeit the rest of the block.
CREATE TABLE IF NOT EXISTS spot_check_absences (
    spot_check_id INTEGER NOT NULL REFERENCES spot_checks(id) ON DELETE CASCADE,
    student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    PRIMARY KEY (spot_check_id, student_id)
);

CREATE TABLE IF NOT EXISTS attendance (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    session_id INTEGER REFERENCES sessions(id) ON DELETE SET NULL,
    date TEXT NOT NULL,
    marked_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
    exit_at TEXT,
    exit_source TEXT NOT NULL DEFAULT 'scan',
    override_note TEXT NOT NULL DEFAULT '',
    confidence REAL NOT NULL
);

CREATE TABLE IF NOT EXISTS notifications (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    session_id INTEGER REFERENCES sessions(id) ON DELETE SET NULL,
    date TEXT NOT NULL,
    channel TEXT NOT NULL DEFAULT 'whatsapp',
    to_phone TEXT NOT NULL,
    body TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('dry_run', 'sent', 'failed')),
    provider TEXT NOT NULL DEFAULT '',
    provider_ref TEXT,
    error TEXT,
    sent_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime'))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_att_daily
    ON attendance(student_id, date) WHERE session_id IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_att_session
    ON attendance(student_id, session_id) WHERE session_id IS NOT NULL;
-- A parent is told about a given day at most once. Dry runs are exempt so the
-- flow stays re-runnable while testing.
CREATE UNIQUE INDEX IF NOT EXISTS ux_notif_sent_once
    ON notifications(student_id, date) WHERE status = 'sent';
"""


def _migrate(conn):
    user_cols = {r["name"] for r in conn.execute("PRAGMA table_info(users)")}
    if user_cols and "must_change_password" not in user_cols:
        conn.execute("ALTER TABLE users ADD COLUMN must_change_password INTEGER NOT NULL DEFAULT 0")
    att_cols = {r["name"] for r in conn.execute("PRAGMA table_info(attendance)")}
    if att_cols and "exit_source" not in att_cols:
        conn.execute("ALTER TABLE attendance ADD COLUMN exit_source TEXT NOT NULL DEFAULT 'scan'")
        conn.execute("ALTER TABLE attendance ADD COLUMN override_note TEXT NOT NULL DEFAULT ''")
    if att_cols and "exit_at" not in att_cols:
        conn.executescript("""
            ALTER TABLE attendance RENAME TO attendance_old;
            CREATE TABLE attendance (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
                session_id INTEGER REFERENCES sessions(id) ON DELETE SET NULL,
                date TEXT NOT NULL,
                marked_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
                exit_at TEXT,
                confidence REAL NOT NULL
            );
            INSERT INTO attendance (id, student_id, date, marked_at, confidence)
                SELECT id, student_id, date, marked_at, confidence FROM attendance_old;
            DROP TABLE attendance_old;
        """)
    sess_cols = {r["name"] for r in conn.execute("PRAGMA table_info(sessions)")}
    if sess_cols and "spot_check_enabled" not in sess_cols:
        conn.execute("ALTER TABLE sessions ADD COLUMN spot_check_enabled INTEGER NOT NULL DEFAULT 0")
    if sess_cols and "entry_until" not in sess_cols:
        conn.execute("ALTER TABLE sessions ADD COLUMN entry_until TEXT NOT NULL DEFAULT ''")
        conn.execute("ALTER TABLE sessions ADD COLUMN exit_from TEXT NOT NULL DEFAULT ''")
        conn.execute("ALTER TABLE sessions ADD COLUMN exit_until TEXT NOT NULL DEFAULT ''")
    stu_cols = {r["name"] for r in conn.execute("PRAGMA table_info(students)")}
    if stu_cols and "parent_phone" not in stu_cols:
        conn.execute("ALTER TABLE students ADD COLUMN parent_phone TEXT NOT NULL DEFAULT ''")
    if stu_cols and "user_id" not in stu_cols:
        conn.execute("ALTER TABLE students ADD COLUMN user_id INTEGER REFERENCES users(id)")
        # Adopt any pre-existing login that used the old username = roll_no
        # convention, so existing students keep working after the upgrade.
        conn.execute(
            """UPDATE students SET user_id = (
                   SELECT u.id FROM users u
                   WHERE u.username = students.roll_no AND u.role = 'student'
               ) WHERE user_id IS NULL"""
        )


@contextmanager
def get_db():
    conn = sqlite3.connect(config.DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def init_db():
    with get_db() as conn:
        _migrate(conn)
        conn.executescript(SCHEMA)
