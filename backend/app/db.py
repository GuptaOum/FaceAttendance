import sqlite3
from contextlib import contextmanager

from . import config

SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('admin', 'teacher', 'student')),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS students (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    owner_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    roll_no TEXT NOT NULL,
    name TEXT NOT NULL,
    class_name TEXT NOT NULL DEFAULT '',
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
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS attendance (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    session_id INTEGER REFERENCES sessions(id) ON DELETE SET NULL,
    date TEXT NOT NULL,
    marked_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
    exit_at TEXT,
    confidence REAL NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_att_daily
    ON attendance(student_id, date) WHERE session_id IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_att_session
    ON attendance(student_id, session_id) WHERE session_id IS NOT NULL;
"""


def _migrate(conn):
    att_cols = {r["name"] for r in conn.execute("PRAGMA table_info(attendance)")}
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
    if sess_cols and "entry_until" not in sess_cols:
        conn.execute("ALTER TABLE sessions ADD COLUMN entry_until TEXT NOT NULL DEFAULT ''")
        conn.execute("ALTER TABLE sessions ADD COLUMN exit_from TEXT NOT NULL DEFAULT ''")
        conn.execute("ALTER TABLE sessions ADD COLUMN exit_until TEXT NOT NULL DEFAULT ''")


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
