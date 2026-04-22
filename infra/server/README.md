# SmarterPillow snoring inference server

YAMNet (via tensorflow-hub) behind a FastAPI endpoint. Deployed to an Azure VM by the Terraform in `../terraform/`. iOS clients call `POST /classify` with a short WAV clip; the server returns the top AudioSet label collapsed to `{Snoring, Snort, Breathing, Speech, Cough, Other}`.

## Run locally

```
python3.11 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
echo "dev-secret" > /tmp/snoring-secret
HMAC_SECRET_FILE=/tmp/snoring-secret uvicorn app:app --host 127.0.0.1 --port 8000
```

## Call it

Python signing helper (`sign.py`):

```python
import hashlib, hmac, time, sys, requests

secret = b"dev-secret"
clip = open(sys.argv[1], "rb").read()
ts = str(int(time.time()))
digest = hashlib.sha256(clip).hexdigest()
sig = hmac.new(secret, f"{ts}\n{digest}".encode(), hashlib.sha256).hexdigest()
r = requests.post(
    "http://127.0.0.1:8000/classify",
    headers={"X-Timestamp": ts, "X-Signature": sig},
    files={"file": ("clip.wav", clip, "audio/wav")},
    data={"sample_rate": "44100"},
)
print(r.status_code, r.json())
```

## Security & privacy notes

- Clip bytes live only in RAM for the duration of one request; they are not written to disk.
- Logs record `label`, `confidence`, and `bytes_length` — no audio, no user identifier.
- HMAC secret is read from `HMAC_SECRET_FILE` at startup; keep it out of the repo.
- Caddy terminates TLS with Let's Encrypt. Certificates live under `/var/lib/caddy`.
