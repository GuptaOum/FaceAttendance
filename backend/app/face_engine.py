import threading

import cv2
import numpy as np
from insightface.app import FaceAnalysis

from . import config
from .antispoof import AntiSpoof
from .db import get_db


class EnrollmentError(Exception):
    pass


class FaceEngine:
    def __init__(self):
        self._analyzer = FaceAnalysis(name="buffalo_l", providers=["CPUExecutionProvider"])
        self._analyzer.prepare(ctx_id=0, det_size=(640, 640))
        self._antispoof = AntiSpoof() if config.ANTISPOOF_ENABLED else None
        self._lock = threading.Lock()
        self._matrix: np.ndarray | None = None
        self._student_ids: list[int] = []
        self.reload_index()

    def _decode(self, image_bytes: bytes) -> np.ndarray:
        arr = np.frombuffer(image_bytes, np.uint8)
        img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
        if img is None:
            raise EnrollmentError("Could not decode image")
        return img

    def _detect(self, img: np.ndarray) -> list:
        with self._lock:
            return self._analyzer.get(img)

    def embed_for_enrollment(self, image_bytes: bytes) -> np.ndarray:
        img = self._decode(image_bytes)
        faces = self._detect(img)
        if len(faces) == 0:
            raise EnrollmentError("No face detected")
        if len(faces) > 1:
            raise EnrollmentError("Multiple faces detected, only the student should be in frame")
        face = faces[0]
        if face.det_score < config.MIN_DET_SCORE:
            raise EnrollmentError("Face detection confidence too low")
        x1, y1, x2, y2 = face.bbox.astype(int)
        if min(x2 - x1, y2 - y1) < config.MIN_FACE_SIZE:
            raise EnrollmentError("Face too small, move closer to the camera")
        crop = img[max(y1, 0):y2, max(x1, 0):x2]
        if crop.size > 0:
            blur = cv2.Laplacian(cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY), cv2.CV_64F).var()
            if blur < config.MIN_BLUR_VAR:
                raise EnrollmentError("Image too blurry, hold the camera steady")
        return face.normed_embedding.astype(np.float32)

    def embed_kiosk_face(self, image_bytes: bytes) -> tuple[np.ndarray | None, str | None]:
        img = self._decode(image_bytes)
        min_height = img.shape[0] * config.KIOSK_MIN_FACE_RATIO
        faces = self._detect(img)
        faces = [
            f for f in faces
            if f.det_score >= config.MIN_DET_SCORE and (f.bbox[3] - f.bbox[1]) >= min_height
        ]
        if not faces:
            return None, "no_face"
        if len(faces) > 1:
            faces.sort(key=lambda f: f.bbox[3] - f.bbox[1], reverse=True)
            h1 = faces[0].bbox[3] - faces[0].bbox[1]
            h2 = faces[1].bbox[3] - faces[1].bbox[1]
            if h1 < h2 * config.KIOSK_DOMINANCE_RATIO:
                return None, "multiple_faces"
        face = faces[0]
        img_h, img_w = img.shape[:2]
        cx = (face.bbox[0] + face.bbox[2]) / 2
        cy = (face.bbox[1] + face.bbox[3]) / 2
        if (abs(cx - img_w / 2) > img_w * config.KIOSK_CENTER_TOLERANCE
                or abs(cy - img_h / 2) > img_h * config.KIOSK_CENTER_TOLERANCE):
            return None, "not_centered"
        if self._antispoof is not None and not self._antispoof.is_live(img, face.bbox):
            return None, "spoof"
        return face.normed_embedding.astype(np.float32), None

    def reload_index(self):
        with get_db() as conn:
            rows = conn.execute(
                """SELECT e.student_id, e.vector, s.owner_id
                   FROM embeddings e JOIN students s ON s.id = e.student_id"""
            ).fetchall()
        if not rows:
            self._matrix = None
            self._student_ids = np.array([], dtype=np.int64)
            self._owner_ids = np.array([], dtype=np.int64)
            return
        self._student_ids = np.array([r["student_id"] for r in rows], dtype=np.int64)
        self._owner_ids = np.array([r["owner_id"] for r in rows], dtype=np.int64)
        self._matrix = np.stack([np.frombuffer(r["vector"], dtype=np.float32) for r in rows])

    def match(
        self, embedding: np.ndarray, owner_id: int, allowed_ids: set[int] | None = None
    ) -> tuple[int, float] | None:
        if self._matrix is None:
            return None
        mask = self._owner_ids == owner_id
        if allowed_ids is not None:
            mask &= np.isin(self._student_ids, list(allowed_ids))
        if not mask.any():
            return None
        sims = self._matrix @ embedding
        sims[~mask] = -1.0
        best = int(np.argmax(sims))
        score = float(sims[best])
        if score < config.MATCH_THRESHOLD:
            return None
        return int(self._student_ids[best]), score

    def find_duplicate(
        self, embeddings: list[np.ndarray], owner_id: int, exclude_student_id: int
    ) -> tuple[int, float] | None:
        if self._matrix is None:
            return None
        mask = (self._owner_ids == owner_id) & (self._student_ids != exclude_student_id)
        if not mask.any():
            return None
        best_id, best_score = None, 0.0
        for emb in embeddings:
            sims = self._matrix @ emb
            sims[~mask] = -1.0
            idx = int(np.argmax(sims))
            if sims[idx] > best_score:
                best_id, best_score = int(self._student_ids[idx]), float(sims[idx])
        if best_id is not None and best_score >= config.DUPLICATE_FACE_THRESHOLD:
            return best_id, best_score
        return None
