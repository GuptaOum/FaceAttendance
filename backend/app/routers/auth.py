from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm

from ..db import get_db
from ..security import create_token, verify_password

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/login")
def login(form: OAuth2PasswordRequestForm = Depends()):
    with get_db() as conn:
        row = conn.execute("SELECT * FROM users WHERE username = ?", (form.username,)).fetchone()
    if row is None or not verify_password(form.password, row["password_hash"]):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Incorrect username or password")
    token = create_token(row["username"], row["role"], row["student_id"])
    return {"access_token": token, "token_type": "bearer", "role": row["role"], "student_id": row["student_id"]}
