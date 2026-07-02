import re

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from pydantic import BaseModel

from ..db import get_db
from ..security import create_token, hash_password, verify_password

router = APIRouter(prefix="/auth", tags=["auth"])

USERNAME_RE = re.compile(r"^[a-zA-Z0-9_.@-]{3,40}$")


class SignupIn(BaseModel):
    username: str
    password: str


@router.post("/signup", status_code=status.HTTP_201_CREATED)
def signup(body: SignupIn):
    username = body.username.strip().lower()
    if not USERNAME_RE.match(username):
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "Username must be 3-40 characters: letters, numbers, _ . @ -",
        )
    if len(body.password) < 6:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Password must be at least 6 characters")
    with get_db() as conn:
        existing = conn.execute("SELECT id FROM users WHERE username = ?", (username,)).fetchone()
        if existing:
            raise HTTPException(status.HTTP_409_CONFLICT, "Username already taken")
        cur = conn.execute(
            "INSERT INTO users (username, password_hash, role) VALUES (?, ?, 'teacher')",
            (username, hash_password(body.password)),
        )
        user_id = cur.lastrowid
    token = create_token(user_id, username, "teacher")
    return {"access_token": token, "token_type": "bearer", "role": "teacher", "username": username}


@router.post("/login")
def login(form: OAuth2PasswordRequestForm = Depends()):
    username = form.username.strip().lower()
    with get_db() as conn:
        row = conn.execute("SELECT * FROM users WHERE username = ?", (username,)).fetchone()
    if row is None or not verify_password(form.password, row["password_hash"]):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Incorrect username or password")
    token = create_token(row["id"], row["username"], row["role"])
    return {"access_token": token, "token_type": "bearer", "role": row["role"], "username": row["username"]}
