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
KIOSK_DOMINANCE_RATIO = float(os.environ.get("KIOSK_DOMINANCE_RATIO", "1.4"))
KIOSK_CENTER_TOLERANCE = float(os.environ.get("KIOSK_CENTER_TOLERANCE", "0.28"))

# Pose gating. face.pose is [pitch, yaw, roll] in degrees; yaw is signed left/right.
# Enrollment deliberately captures slight left/right poses (~15-25 deg), so its limit
# only rejects hard profiles where the ArcFace embedding degrades.
MAX_ENROLL_YAW = float(os.environ.get("MAX_ENROLL_YAW", "45.0"))
MAX_KIOSK_YAW = float(os.environ.get("MAX_KIOSK_YAW", "35.0"))

# Illumination gating, measured as mean grey level (0-255) over the face crop.
# Well-lit faces measure ~150-175; the bounds below reject unusable extremes only.
MIN_FACE_BRIGHTNESS = float(os.environ.get("MIN_FACE_BRIGHTNESS", "60.0"))
MAX_FACE_BRIGHTNESS = float(os.environ.get("MAX_FACE_BRIGHTNESS", "200.0"))
# Left/right brightness difference as a fraction of the brighter half; catches
# harsh side-light and backlight, which bias the embedding. Measured: evenly lit
# faces sit at 0.03-0.08, harsh side-light at 0.23+. Calibrated on a small sample,
# so it is deliberately loose - raise it if legitimate enrollments get rejected.
MAX_BRIGHTNESS_IMBALANCE = float(os.environ.get("MAX_BRIGHTNESS_IMBALANCE", "0.25"))

ANTISPOOF_ENABLED = os.environ.get("ANTISPOOF_ENABLED", "1") == "1"
ANTISPOOF_THRESHOLD = float(os.environ.get("ANTISPOOF_THRESHOLD", "0.5"))
ANTISPOOF_ON_ENROLL = os.environ.get("ANTISPOOF_ON_ENROLL", "1") == "1"
DUPLICATE_FACE_THRESHOLD = float(os.environ.get("DUPLICATE_FACE_THRESHOLD", "0.55"))
MIN_ENROLL_IMAGES = int(os.environ.get("MIN_ENROLL_IMAGES", "5"))
MAX_ENROLL_IMAGES = int(os.environ.get("MAX_ENROLL_IMAGES", "10"))

# --- Parent absence notifications -------------------------------------------
# Defaults to "dryrun": every message is rendered, logged and visible in the API,
# but nothing is transmitted. Recognition has false negatives (a present student
# can be missed in poor light), so a real provider should only be switched on
# once you trust the absent list. Sending is always teacher-approved per student.
WHATSAPP_PROVIDER = os.environ.get("WHATSAPP_PROVIDER", "dryrun")  # dryrun | twilio
# Sender's WhatsApp number in E.164, e.g. +14155238886 (Twilio sandbox number).
WHATSAPP_FROM = os.environ.get("WHATSAPP_FROM", "")
TWILIO_ACCOUNT_SID = os.environ.get("TWILIO_ACCOUNT_SID", "")
TWILIO_AUTH_TOKEN = os.environ.get("TWILIO_AUTH_TOKEN", "")
WHATSAPP_TIMEOUT = float(os.environ.get("WHATSAPP_TIMEOUT", "15"))
SCHOOL_NAME = os.environ.get("SCHOOL_NAME", "School")
ABSENCE_TEMPLATE = os.environ.get(
    "ABSENCE_TEMPLATE",
    "Dear Parent, {name} (Roll {roll_no}) was marked absent for {label} on {date}. "
    "Please contact the school if this is incorrect. - {school}",
)
