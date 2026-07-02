import os

import cv2
import numpy as np
import onnxruntime as ort

from . import config

MODEL_PATH = os.path.join(os.path.dirname(__file__), "..", "models", "antispoof_print_replay_128.onnx")


class AntiSpoof:
    def __init__(self):
        self._session = ort.InferenceSession(MODEL_PATH, providers=["CPUExecutionProvider"])
        self._input_name = self._session.get_inputs()[0].name

    def _increased_crop(self, img: np.ndarray, bbox: np.ndarray, bbox_inc: float = 1.5) -> np.ndarray:
        real_h, real_w = img.shape[:2]
        x1, y1, x2, y2 = bbox
        w, h = x2 - x1, y2 - y1
        side = int(max(w, h) * bbox_inc)
        xc, yc = x1 + w / 2, y1 + h / 2
        x, y = int(xc - side / 2), int(yc - side / 2)
        cx1, cy1 = max(x, 0), max(y, 0)
        cx2, cy2 = min(x + side, real_w), min(y + side, real_h)
        crop = img[cy1:cy2, cx1:cx2]
        crop = cv2.copyMakeBorder(
            crop, cy1 - y, y + side - cy2, cx1 - x, x + side - cx2,
            cv2.BORDER_CONSTANT, value=(0, 0, 0),
        )
        return crop

    def live_score(self, img_bgr: np.ndarray, bbox: np.ndarray) -> float:
        crop = self._increased_crop(img_bgr, bbox.astype(int))
        rgb = cv2.cvtColor(crop, cv2.COLOR_BGR2RGB)
        rgb = cv2.resize(rgb, (128, 128))
        blob = rgb.transpose(2, 0, 1).astype(np.float32)[None] / 255.0
        logits = self._session.run(None, {self._input_name: blob})[0][0]
        probs = np.exp(logits) / np.sum(np.exp(logits))
        if int(np.argmax(probs)) != 0:
            return 0.0
        return float(probs[0])

    def is_live(self, img_bgr: np.ndarray, bbox: np.ndarray) -> bool:
        return self.live_score(img_bgr, bbox) >= config.ANTISPOOF_THRESHOLD
