FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libsndfile1 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/snoring/server
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

ENV HMAC_SECRET_FILE=/etc/snoring/secret
ENV TF_CPP_MIN_LOG_LEVEL=2

EXPOSE 8000
CMD ["gunicorn", "--workers", "1", "--threads", "4", "--timeout", "30", \
     "--bind", "0.0.0.0:8000", \
     "--worker-class", "uvicorn.workers.UvicornWorker", \
     "app:app"]
