"""Issue read-only logins for students created before logins existed.

Idempotent: students that already have a login are skipped. Username is the
roll number, falling back to "<roll_no>.<teacher>" when another teacher has
already claimed it. Initial password is the roll number.

Run inside the backend container:
    python backfill_student_logins.py
"""

from app.db import get_db, init_db
from app.routers.students import _create_student_login

init_db()

with get_db() as conn:
    students = conn.execute(
        """SELECT s.id, s.roll_no, s.name, u.username AS owner_username
           FROM students s JOIN users u ON u.id = s.owner_id
           WHERE s.user_id IS NULL ORDER BY s.roll_no"""
    ).fetchall()

    if not students:
        print("All students already have logins - nothing to do.")

    for s in students:
        username, user_id = _create_student_login(conn, s["roll_no"], s["owner_username"])
        if username is None:
            print(f"  SKIPPED {s['name']} ({s['roll_no']}): could not allocate a username")
            continue
        conn.execute("UPDATE students SET user_id = ? WHERE id = ?", (user_id, s["id"]))
        print(f"  {s['name']:<20} login={username:<16} password={s['roll_no']}")

with get_db() as conn:
    n = conn.execute("SELECT COUNT(*) FROM users WHERE role = 'student'").fetchone()[0]
    print(f"student logins now: {n}")
