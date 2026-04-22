import csv
import hashlib
import hmac
import io
import logging
import os
import time

import numpy as np
import soundfile as sf
import tensorflow as tf
import tensorflow_hub as hub
from fastapi import FastAPI, Header, HTTPException, UploadFile, Form, File
from scipy.signal import resample_poly

YAMNET_HANDLE = "https://tfhub.dev/google/yamnet/1"
YAMNET_SR = 16000
MAX_CLIP_SECONDS = 30
MAX_TIMESTAMP_SKEW_SECONDS = 300

# YAMNet class names that we surface directly to the app. Anything outside
# this set gets relabeled as "Other" before being returned. The app's live
# sleep-tracking path only treats Snoring/Snort as snores — everything else
# demotes the event — but the Mic Test diagnostic view displays whatever
# label comes back, so enriching this set gives users clearer feedback.
APP_LABELS = {
    "Snoring", "Snort", "Breathing", "Speech", "Cough",
    "Dog", "Bark", "Howl", "Growling", "Whimper (dog)", "Yip", "Bow-wow",
    "Cat", "Meow", "Purr", "Hiss", "Caterwaul",
}

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("snoring")

_secret_path = os.environ.get("HMAC_SECRET_FILE", "/etc/snoring/secret")
with open(_secret_path, "rb") as f:
    HMAC_SECRET = f.read().strip()
if not HMAC_SECRET:
    raise RuntimeError(f"empty HMAC secret at {_secret_path}")

log.info("loading YAMNet")
_model = hub.load(YAMNET_HANDLE)
_class_map_path = _model.class_map_path().numpy().decode()
with tf.io.gfile.GFile(_class_map_path) as f:
    _class_names = [row["display_name"] for row in csv.DictReader(f)]
log.info("YAMNet loaded with %d classes", len(_class_names))

app = FastAPI()


def _verify_signature(timestamp: str, signature: str, body: bytes) -> None:
    try:
        ts = int(timestamp)
    except (TypeError, ValueError):
        raise HTTPException(status_code=401, detail="bad timestamp")
    if abs(time.time() - ts) > MAX_TIMESTAMP_SKEW_SECONDS:
        raise HTTPException(status_code=401, detail="timestamp out of range")
    digest = hashlib.sha256(body).hexdigest()
    payload = f"{ts}\n{digest}".encode()
    expected = hmac.new(HMAC_SECRET, payload, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(expected, signature or ""):
        raise HTTPException(status_code=401, detail="bad signature")


def _to_yamnet_waveform(wav_bytes: bytes) -> np.ndarray:
    data, sr = sf.read(io.BytesIO(wav_bytes), dtype="float32", always_2d=True)
    if data.shape[0] / sr > MAX_CLIP_SECONDS:
        raise HTTPException(status_code=413, detail="clip too long")
    mono = data.mean(axis=1)
    if sr != YAMNET_SR:
        # resample_poly handles common SRs (44100 → 16000 via up=160 down=441)
        g = np.gcd(sr, YAMNET_SR)
        mono = resample_poly(mono, YAMNET_SR // g, sr // g).astype(np.float32)
    return mono


AMBIENT_LABELS = {
    "Silence",
    "Inside, small room",
    "Inside, large room or hall",
    "Outside, urban or manmade",
    "Outside, rural or natural",
    "White noise",
    "Pink noise",
}

# When multiple APP_LABELS tie (or are within the NEAR_TOP_EPSILON below) we
# prefer the more specific / sleep-relevant one. A snoring clip where YAMNet
# rates "Snoring" and "Breathing" both at ~1.0 should land on "Snoring",
# because the live sleep-tracking path only counts "Snoring"/"Snort" as
# actual snoring events — "Breathing" would demote it.
APP_LABEL_PRIORITY = [
    "Snoring", "Snort", "Cough",
    "Bark", "Howl", "Growling", "Whimper (dog)", "Yip", "Bow-wow", "Dog",
    "Meow", "Hiss", "Purr", "Caterwaul", "Cat",
    "Breathing", "Speech",
]
_APP_LABEL_RANK = {name: i for i, name in enumerate(APP_LABEL_PRIORITY)}
NEAR_TOP_EPSILON = 0.05


def _classify(waveform: np.ndarray):
    scores, _embeddings, _spec = _model(waveform)
    # Max-pool per class across YAMNet's 0.96 s frames. Previously we
    # averaged frame scores, which meant a 1-second bark in a 10-second
    # clip got drowned by 9 frames of silence. Max-pool surfaces burst
    # sounds (barks, snores, meows, coughs) correctly.
    peak_scores = tf.reduce_max(scores, axis=0).numpy()

    # Keep 10 candidates so we can filter out ambient-only "winners."
    top_idx = np.argsort(peak_scores)[::-1][:10]
    candidates = [
        {"label": _class_names[i], "confidence": float(peak_scores[i])}
        for i in top_idx
    ]

    # Pick the winning label:
    #   1. Prefer APP_LABELS (what the app actually displays). If multiple
    #      APP_LABELS are within NEAR_TOP_EPSILON of the best, pick the
    #      one with the highest priority (Snoring > Breathing, etc.) so
    #      Dog/Bark/Snoring beat their generic siblings.
    #   2. If no APP_LABEL cleared 0.15, fall through to any non-ambient
    #      label. Surfaces meaningful content when YAMNet heard something
    #      real but outside our curated bucket list.
    #   3. Last resort: the raw top-1 (likely Silence or similar).
    winner = candidates[0]
    app_candidates = [
        c for c in candidates
        if c["label"] in APP_LABELS and c["confidence"] >= 0.15
    ]
    if app_candidates:
        best_conf = max(c["confidence"] for c in app_candidates)
        near_top = [c for c in app_candidates if c["confidence"] >= best_conf - NEAR_TOP_EPSILON]
        winner = min(
            near_top,
            key=lambda c: _APP_LABEL_RANK.get(c["label"], 1_000)
        )
    else:
        for entry in candidates:
            if entry["label"] not in AMBIENT_LABELS and entry["confidence"] >= 0.15:
                winner = entry
                break

    top_5 = candidates[:5]
    label = winner["label"] if winner["label"] in APP_LABELS else "Other"
    return label, float(winner["confidence"]), top_5


@app.get("/health")
def health():
    return {"ok": True}


@app.post("/classify")
async def classify(
    file: UploadFile = File(...),
    sample_rate: int = Form(...),  # retained for client symmetry; SR comes from WAV header
    x_timestamp: str = Header(..., alias="X-Timestamp"),
    x_signature: str = Header(..., alias="X-Signature"),
):
    body = await file.read()
    try:
        _verify_signature(x_timestamp, x_signature, body)
        waveform = _to_yamnet_waveform(body)
        label, confidence, top_5 = _classify(waveform)
        # Top-5 lets us see what YAMNet actually heard without cross-
        # referencing the iOS client console. Compact one-line format:
        #   top5=[Speech:0.61 Silence:0.25 Bark:0.08 Dog:0.04 Howl:0.01]
        top5_str = " ".join(f"{e['label']}:{e['confidence']:.2f}" for e in top_5)
        log.info(
            "classified label=%s conf=%.3f bytes=%d top5=[%s]",
            label, confidence, len(body), top5_str
        )
        return {"label": label, "confidence": confidence, "top_5": top_5}
    finally:
        # Clip never touches disk and is dropped from memory on return.
        del body
