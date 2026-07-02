import os

DB_PATH = os.environ.get("DB_PATH", os.path.join(os.path.dirname(__file__), "..", "attendance.db"))
JWT_SECRET = os.environ.get("JWT_SECRET", "change-me-in-production")
JWT_ALGORITHM = "HS256"
JWT_EXPIRE_MINUTES = int(os.environ.get("JWT_EXPIRE_MINUTES", "720"))

MATCH_THRESHOLD = float(os.environ.get("MATCH_THRESHOLD", "0.45"))
MIN_DET_SCORE = float(os.environ.get("MIN_DET_SCORE", "0.60"))
MIN_FACE_SIZE = int(os.environ.get("MIN_FACE_SIZE", "80"))
MIN_BLUR_VAR = float(os.environ.get("MIN_BLUR_VAR", "60.0"))
KIOSK_MIN_FACE_RATIO = float(os.environ.get("KIOSK_MIN_FACE_RATIO", "0.15"))
MIN_ENROLL_IMAGES = int(os.environ.get("MIN_ENROLL_IMAGES", "5"))
MAX_ENROLL_IMAGES = int(os.environ.get("MAX_ENROLL_IMAGES", "10"))
