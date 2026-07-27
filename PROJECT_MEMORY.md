---
name: face-attendance-unified
description: "FaceAttendance — FastAPI+InsightFace backend, Flutter app (enrollment + kiosk), multi-tenant, deployed on EC2"
metadata:
  node_type: memory
  type: project
---

Started 2026-07-02 as a separate repo from ScholarRAG: `E:\proj\FaceAttendance` — AI face attendance system.

## Stack
- **Backend**: FastAPI + InsightFace `buffalo_l` (ArcFace 512-d embeddings, no training — enrollment only), OpenCV quality checks (blur/size/single-face), SQLite (`students`, `embeddings` BLOB, `attendance` UNIQUE(student_id,date), `users`). Venv at `backend\venv` (Python 3.14). Admin seed: `admin`/`admin123`. Cosine `MATCH_THRESHOLD=0.45`, env-tunable.
- **App**: Flutter in `app\` (org `com.faceattendance`, project `face_attendance`). Screens: login (server URL + JWT), admin home, enroll (5 guided poses, front camera, oval overlay), kiosk (2s timer capture → `/attendance/recognize`), report, student self-view. No MLKit in v1 — backend gives positioning feedback directly.
- Verified: full HTTP API flow tested with a bundled InsightFace test image; `flutter analyze` clean; widget test passes.
- Target device: user wanted an iPad kiosk — flagged that iOS needs a Mac + $99/yr Apple account; an Android tablet + sideloaded APK was recommended instead.
- Scale: ~50-60 students × 5-10 images; brute-force cosine matching in memory, index reloaded on enroll/delete.

## Multi-tenant (since 2026-07-02)
Teacher self-signup (`/auth/signup`), students have `owner_id`, recognition/reports/CRUD all scoped per teacher (isolation test-verified). Kiosk rules: `KIOSK_MIN_FACE_RATIO=0.15` (ignore far faces), `KIOSK_DOMINANCE_RATIO=1.4` (closest-in-queue wins), `KIOSK_CENTER_TOLERANCE=0.28` (must be in the oval), `multiple_faces`/`not_centered` rejection reasons.

## Production deployment
EC2 (ap-south-1) `i-00c50e742d73480ac` t3.medium, Elastic IP **3.109.177.77** (baked into the app as `kDefaultServer`), SG `sg-0dca629c63e847a32` (80 public, 22 user-IP-only), key `C:\Users\hp\.ssh\face-attendance.pem`. Docker compose in `~/face-attendance` with volume `attendance-data` + random `JWT_SECRET` in `.env`. Deploy: `git archive` → scp → `docker compose up -d --build`.

**This same EC2 box also co-hosts the vision-motion-lab Sudoku API** (see `G:\PycharmProjects\vision-motion-lab\PROJECT_MEMORY.md`) on port 8000, while FaceAttendance itself stays on port 80.

## Notes
- Kotlin incremental disabled in `gradle.properties` (Windows cache-lock fix).
- Outstanding: HTTPS/domain (needed for Play Store), DB backups, admin password change, rate limiting on signup.
