import re

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from pydantic import BaseModel

from ..db import get_db
from ..security import create_token, get_current_user, hash_password, verify_password

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
    return {
        "access_token": token, "token_type": "bearer", "role": row["role"],
        "username": row["username"],
        "must_change_password": bool(row["must_change_password"]),
    }


class ChangePasswordIn(BaseModel):
    current_password: str
    new_password: str


@router.post("/change-password")
def change_password(body: ChangePasswordIn, user: dict = Depends(get_current_user)):
    """Change your own password.

    This is the one write a student token may perform, and it only ever touches
    the caller's own row. Student accounts are created with a roll-number
    password and must_change_password set, so this is how they clear it.
    """
    if len(body.new_password) < 6:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Password must be at least 6 characters")
    with get_db() as conn:
        row = conn.execute("SELECT * FROM users WHERE id = ?", (user["id"],)).fetchone()
        if row is None or not verify_password(body.current_password, row["password_hash"]):
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Current password is incorrect")
        if body.new_password == body.current_password:
            raise HTTPException(
                status.HTTP_422_UNPROCESSABLE_ENTITY,
                "New password must be different from the current one",
            )
        conn.execute(
            "UPDATE users SET password_hash = ?, must_change_password = 0 WHERE id = ?",
            (hash_password(body.new_password), user["id"]),
        )
    return {"changed": True}
