FROM python:3.12-slim

WORKDIR /app
ENV PYTHONUNBUFFERED=1 \
    HF_HOME=/root/.cache/huggingface

COPY requirements.txt .
ARG GPU_VENDOR=cpu
RUN case "$GPU_VENDOR" in \
        nvidia) TORCH_INDEX_URL=https://download.pytorch.org/whl/cu121 ;; \
        cpu)    TORCH_INDEX_URL=https://download.pytorch.org/whl/cpu ;; \
        *) echo "Unknown GPU_VENDOR: $GPU_VENDOR (expected cpu or nvidia)" >&2; exit 1 ;; \
    esac \
    && pip install --no-cache-dir torch==2.4.1 --index-url $TORCH_INDEX_URL \
    && pip install --no-cache-dir -r requirements.txt

COPY src/ ./src/
COPY config.yml .
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh

EXPOSE 50051
ENTRYPOINT ["./entrypoint.sh"]
CMD ["uvicorn", "src.server:app", "--host", "0.0.0.0", "--port", "50051"]
