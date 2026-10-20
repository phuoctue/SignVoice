"""OpenCV camera diagnostics, alongside the runtime's LK hand recovery.

Diagnostics never change model pixels, thresholds, labels or observed landmarks.
"""
import cv2
import numpy as np


class OpenCVCameraAnalysis:
    def __init__(self):
        self.last_quality_time = -float('inf')
        self.quality = None

    def analyze(self, frame, hands, motion, now):
        height, width = frame.shape[:2]
        regions = []
        crops = []
        for hand in hands:
            points = np.asarray([[p.x * width, p.y * height] for p in hand], np.float32)
            if len(points) < 3 or not np.isfinite(points).all():
                continue
            points[:, 0] = np.clip(points[:, 0], 0, width - 1)
            points[:, 1] = np.clip(points[:, 1], 0, height - 1)
            hull = cv2.convexHull(np.rint(points).astype(np.int32)).reshape(-1, 2)
            x, y, w, h = cv2.boundingRect(hull)
            if w < 8 or h < 8:
                continue
            regions.append(dict(
                box=[round(x / width, 5), round(y / height, 5), round(w / width, 5), round(h / height, 5)],
                hull=[[round(float(px) / width, 5), round(float(py) / height, 5)] for px, py in hull],
            ))
            crops.append(frame[y:y + h, x:x + w])

        # Measure at 2 Hz; preserve camera sampling capacity for landmark detection.
        if self.quality is None or now - self.last_quality_time >= .5:
            self.last_quality_time = now
            images = crops or [frame]
            means, sharpness = [], []
            for image in images:
                if image.shape[1] > 320:
                    factor = 320 / image.shape[1]
                    image = cv2.resize(image, (320, max(1, round(image.shape[0] * factor))), interpolation=cv2.INTER_AREA)
                gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
                means.append(float(cv2.mean(gray)[0]))
                sharpness.append(float(cv2.Laplacian(gray, cv2.CV_32F).var()))
            brightness = float(np.mean(means))
            warnings = []
            if brightness < 50:
                warnings.append('Khung hình thiếu sáng; thử tăng ánh sáng phía trước.')
            elif brightness > 215:
                warnings.append('Khung hình quá sáng; tránh ánh đèn chiếu thẳng vào tay.')
            if crops and min(sharpness) < 35:
                warnings.append('Vùng tay có thể bị nhòe; lau ống kính và giữ đủ sáng.')
            self.quality = dict(brightness=round(brightness, 1),
                laplacian_variance=round(float(min(sharpness)), 1),
                scope='hand_regions' if crops else 'frame', warnings=warnings,
                advisory_only=True)

        # These are measured pixel correspondences from forward/backward checked LK,
        # not guessed hand joints. A missing hand still requires detector confirmation.
        vectors = []
        for start, end in getattr(motion, 'arrows', [])[:40]:
            points = np.asarray([start, end], np.float32)
            if points.shape != (2, 2) or not np.isfinite(points).all():
                continue
            if np.any(points < 0) or np.any(points[:, 0] >= width) or np.any(points[:, 1] >= height):
                continue
            vectors.append([[round(float(x) / width, 5), round(float(y) / height, 5)] for x, y in points])

        return dict(enabled=True, version=cv2.__version__, regions=regions,
            flow_vectors=vectors, flow_method='Lucas-Kanade forward-backward',
            recovery_guidance_enabled=motion is not None, quality=self.quality)
