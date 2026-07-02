# Face Attendance System

AI-powered student attendance: enroll a student once with 5–10 face photos, then attendance is marked automatically when they stand in front of the kiosk camera.

- **Backend:** FastAPI + InsightFace (ArcFace embeddings, buffalo_l) + OpenCV + SQLite
- **App:** Flutter (Android / iOS) — admin dashboard, guided face enrollment, kiosk mode, reports, student self-view

## How recognition works

1. **Enrollment** — 5–10 photos per student are passed through ArcFace. Each face becomes a 512-dim embedding stored in SQLite. Blurry, small, or multi-face images are rejected with a reason.
2. **Recognition** — the kiosk captures a frame every 2 seconds. The backend detects the largest face, embeds it, and compares against all enrolled embeddings by cosine similarity. Best match above `MATCH_THRESHOLD` (default 0.45) marks attendance; one record per student per day.

No model training or GPU is needed — adding a new student is just enrollment.

## Run the backend

```
cd backend
python -m venv venv
venv\Scripts\pip install -r requirements.txt
venv\Scripts\python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

First start downloads the buffalo_l model pack (~280 MB) to `~/.insightface`.
Default admin login: `admin` / `admin123` (change `JWT_SECRET` and the password in production).
API docs: `http://localhost:8000/docs`

### Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `DB_PATH` | `backend/attendance.db` | SQLite location |
| `JWT_SECRET` | change-me-in-production | Token signing key |
| `MATCH_THRESHOLD` | 0.45 | Min cosine similarity to accept a match |
| `MIN_DET_SCORE` | 0.60 | Min face-detection confidence |
| `MIN_FACE_SIZE` | 80 | Min face box size (px) at enrollment |
| `MIN_BLUR_VAR` | 60.0 | Min sharpness (Laplacian variance) at enrollment |

## Run the app

```
cd app
flutter pub get
flutter run
```

On the login screen enter the server URL (e.g. `http://<your-pc-lan-ip>:8000` — phone and PC must be on the same network), then `admin` / `admin123`.

**Workflow:** Add Student → tap the camera icon → capture 5 guided poses → Upload. Then open **Kiosk Mode** and point the device at students; attendance is marked automatically. Students log in with their roll number (default password = roll number) to see their own history.

## API summary

| Endpoint | Role | Purpose |
|---|---|---|
| `POST /auth/login` | — | JWT login (admin or student) |
| `POST /students` | admin | Register student (also creates their login) |
| `GET /students` | admin | List students + enrollment status |
| `POST /students/{id}/enroll` | admin | Upload 5–10 face images |
| `DELETE /students/{id}` | admin | Remove student, embeddings, attendance |
| `POST /attendance/recognize` | admin | Recognize one frame, mark attendance |
| `GET /attendance?day=YYYY-MM-DD` | admin | Present/absent report |
| `GET /attendance/me` | student | Own attendance history |
