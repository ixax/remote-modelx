"""FastAPI server exposing cross-encoder reranking as a standalone HTTP
service, so consumers (mcp-server) don't need to depend on
sentence-transformers/torch themselves.

This file is the route handler + wiring only -- config loading and model
loading/scoring live in libs/. Env vars and config.yml are read *only*
here; libs/ functions take what they need as arguments.

The model is loaded eagerly at import time (not lazily, unlike mcp-server's
old in-process reranker) -- this service's only job is reranking, so
there's no "start fast for a handshake" concern to trade off against;
slower startup while the checkpoint downloads/loads is the whole point of
splitting this out into its own service instead of blocking mcp-server's
startup. Host/port aren't read here -- uvicorn's `--host`/`--port` CLI
args (see Dockerfile/docker-compose.yml) own binding; the app itself
doesn't need to know its own address.
"""

from __future__ import annotations

import time
from pathlib import Path

from environs import Env
from fastapi import FastAPI
from pydantic import BaseModel

import torch

from .libs.config import RerankerConfig, load_config
from .libs.cpu import detect_num_threads
from .libs.logging_config import configure_logging, get_logger
from .libs.model import load_model, score

env = Env()
RERANKER_MODEL = env.str("RERANKER_MODEL")
# Derived from this container's actual cgroup `cpus:` quota (see libs/cpu.py)
# instead of a RERANKER_NUM_THREADS env var that would need to be kept in
# sync with docker-compose.yml's `cpus:` limit by hand -- see libs/model.py's
# load_model() docstring for why torch needs this at all.
RERANKER_NUM_THREADS = detect_num_threads()

configure_logging()
logger = get_logger(__name__)

raw_config = load_config(Path("config.yml"))
raw_config.raw["model"] = RERANKER_MODEL
config = raw_config.validate(RerankerConfig)

# CrossEncoder picks cuda over cpu on its own (see libs/model.py) -- logged
# here so "why is this slow" / "is the GPU overlay actually doing anything"
# don't require reading source to answer.
_device = "cuda" if torch.cuda.is_available() else "cpu"
logger.info(
    "loading reranker model %s (max_length=%d, num_threads=%d, device=%s) -- "
    "downloads from Hugging Face on first run if not already cached, can take a while",
    config.model,
    config.max_length,
    RERANKER_NUM_THREADS,
    _device,
)
_model = load_model(config.model, config.max_length, RERANKER_NUM_THREADS)
logger.info("reranker ready, listening for /rerank requests")

app = FastAPI()


class RerankRequest(BaseModel):
    query: str
    documents: list[str]


class RerankResponse(BaseModel):
    # Scores aligned 1:1 with `documents` in the request, in the same order
    # (not sorted) -- the caller sorts/truncates as needed.
    scores: list[float]
    model: str
    duration_ms: float


@app.post("/rerank")
def rerank(request: RerankRequest) -> RerankResponse:
    logger.info("scoring %d document(s) with %s", len(request.documents), config.model)
    start = time.perf_counter()
    scores = score(_model, request.query, request.documents)
    duration_ms = (time.perf_counter() - start) * 1000
    return RerankResponse(scores=scores, model=config.model, duration_ms=duration_ms)
