# AGENTS.md -- remote-modelx/

Standalone deployment, decoupled from any consumer project's own compose network -- see `README.md` for the "why" and how consumer services connect (`OLLAMA_HOST`/`OLLAMA_PORT`, `RERANKER_HOST`/`RERANKER_PORT`).

## Ollama

- `ollama-pull`'s script lives in `ollama/entrypoint.sh`, bind-mounted rather than inlined as `command:` in `docker-compose.yml`.
- `OLLAMA_KEEP_ALIVE: "-1"` on the `ollama` service (never auto-unload a loaded model) is why `entrypoint.sh` runs a throwaway `ollama run "$MODEL" "hi"` after each `pull` -- warms the model into memory once at pull time instead of eating the cold-load stall on a consumer's first real request.
- `docker-compose.gpu.yml` only touches the `ollama` service's `deploy.resources.reservations` -- it's an override applied with `-f docker-compose.yml -f docker-compose.gpu.yml`, never a replacement for the base file.

## Reranker

- `reranker/src/server.py` is handlers + wiring only -- config schema, model loading, and scoring live in `reranker/src/libs/` (`config.py`, `model.py`); those functions take what they need as arguments rather than reading env/config themselves.
- `reranker/src/libs/logging_config.py` and `yaml_config.py` are this service's own config-loading/logging code, not shared with anything else in `remote-modelx/`.
- `reranker/src/libs/cpu.py` derives torch's thread count from the `reranker` service's `cpus:` cgroup quota at startup, so `docker-compose.yml`'s `cpus:` limit is the only place that number is set -- see `reranker/src/libs/model.py`'s `load_model()` docstring.
- The reranker model is loaded eagerly at import time (`server.py`), not lazily -- this service's only job is reranking, so there's no "start fast for a handshake" concern to trade off against slow startup while the checkpoint downloads.

## Both

No env vars are read anywhere except in `docker-compose.yml`/`ollama/entrypoint.sh`/`reranker/src` themselves -- there's no other app code here to keep in sync.

## docker-compose.yml conventions

- Every env var read into `docker-compose.yml` (via `${VAR}`/`${VAR:-default}`) must be declared once as a scalar in the top-level `x-vars:` block and referenced everywhere else by YAML anchor (`&name` / `*name`), never inlined a second time in a service's `environment:`/`ports:`/etc. This keeps each var's default in exactly one place instead of risking copies drifting apart.
- Port mappings use the long `target:`/`published:` form (with `published: *anchor`), not the short `"${VAR:-default}:port"` string -- concatenating an anchor into a flow-scalar string isn't valid YAML, so the long form is the only way to keep the port anchored too.
