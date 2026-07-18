FROM python:3.12-slim

WORKDIR /app
ENV PYTHONUNBUFFERED=1 \
    HF_HOME=/root/.cache/huggingface

COPY requirements.txt .
# CPU by default so pip doesn't grab a multi-GB CUDA build on machines
# without an NVIDIA GPU. Override with --build-arg TORCH_INDEX_URL=
# https://download.pytorch.org/whl/cu121 (or whichever CUDA build matches
# the host driver) for a GPU build -- see docker-compose.gpu.yml, which
# sets this automatically.
ARG TORCH_INDEX_URL=https://download.pytorch.org/whl/cpu
RUN pip install --no-cache-dir torch==2.4.1 --index-url $TORCH_INDEX_URL \
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
