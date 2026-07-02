from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .db import get_db, init_db
from .face_engine import FaceEngine
from .routers import attendance, auth, students
from .security import hash_password


def seed_admin():
    with get_db() as conn:
        row = conn.execute("SELECT COUNT(*) AS n FROM users WHERE role = 'admin'").fetchone()
        if row["n"] == 0:
            conn.execute(
                "INSERT INTO users (username, password_hash, role) VALUES ('admin', ?, 'admin')",
                (hash_password("admin123"),),
            )


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    seed_admin()
    app.state.engine = FaceEngine()
    yield


app = FastAPI(title="Face Attendance API", version="1.0.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(students.router)
app.include_router(attendance.router)


@app.get("/health")
def health():
    return {"status": "ok", "version": app.version}
