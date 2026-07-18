FROM python:3.12-slim

WORKDIR /app
ENV PYTHONUNBUFFERED=1 \
    HF_HOME=/root/.cache/huggingface

COPY requirements.txt .
# GPU_VENDOR picks which torch wheel gets installed -- cpu (default, so
# plain `docker compose up` doesn't pull a multi-GB CUDA/ROCm build on a
# machine with no GPU), nvidia, or amd. docker-compose.gpu.yml sets
# nvidia, docker-compose.gpu-amd.yml sets amd; nothing else about the
# wheel choice needs to leave this file. For an older NVIDIA driver that
# doesn't support cu121, edit the nvidia case below (e.g. cu118) and
# rebuild.
ARG GPU_VENDOR=cpu
RUN case "$GPU_VENDOR" in \
        nvidia) TORCH_INDEX_URL=https://download.pytorch.org/whl/cu121 ;; \
        amd)    TORCH_INDEX_URL=https://download.pytorch.org/whl/rocm6.1 ;; \
        cpu)    TORCH_INDEX_URL=https://download.pytorch.org/whl/cpu ;; \
        *) echo "Unknown GPU_VENDOR: $GPU_VENDOR (expected cpu, nvidia, or amd)" >&2; exit 1 ;; \
    esac \
    && pip install --no-cache-dir torch==2.4.1 --index-url $TORCH_INDEX_URL \
    && pip install --no-cache-dir -r requirements.txt

COPY src/ ./src/
COPY config.yml .
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh

EXPOSE 50051
# entrypoint.sh skips startup (exit 0) when RERANKER_MODEL is unset --
# see that script for why.
ENTRYPOINT ["./entrypoint.sh"]
# CMD (not baked into ENTRYPOINT) so docker-compose's `command:` can freely
# replace this, e.g. append --reload for dev. `src.server:app` is the ASGI
# app exposed at module level in src/server.py. config.yml stays at /app
# (not /app/src) -- src/server.py reads it as a plain relative path, which
# resolves against uvicorn's cwd (/app), not the package's own location.
CMD ["uvicorn", "src.server:app", "--host", "0.0.0.0", "--port", "50051"]
