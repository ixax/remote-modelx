# remote-modelx

A standalone Docker Compose deployment of [Ollama](https://ollama.com/) and a cross-encoder reranking HTTP service, meant to run together and be copied into another project wholesale. Not on the same Docker network as any consumer project -- consumer services reach these over the host (`OLLAMA_HOST`/`OLLAMA_PORT`, `RERANKER_HOST`/`RERANKER_PORT` in the consumer's own `.env`), not via container-name DNS.

## Quick start

```bash
cp .env.example .env   # set OLLAMA_MODELS, e.g. "gemma3:4b,embeddinggemma:300m", if you need Ollama models; RERANKER_MODEL (ships a working default) if you need reranking
make up
docker compose logs -f ollama-pull   # watch the Ollama model pull -- can take minutes
docker compose logs -f reranker      # watch it download + load RERANKER_MODEL on startup
```

On a host with an NVIDIA GPU reachable from Docker:

```bash
make up-gpu-nvidia
```

On a host with a ROCm-capable AMD GPU reachable from Docker:

```bash
make up-gpu-amd
```

Once everything's up, optionally sanity-check the Ollama models by hand:

```bash
make smoketest
```

## What's here

- **`docker-compose.yml`** -- `ollama` (server, port `${OLLAMA_PORT:-11434}`), `ollama-pull` (one-shot job that pulls + warms every model in `OLLAMA_MODELS`), `model-smoketest` (manual, opt-in -- see below), and `reranker` (cross-encoder HTTP service, port `${RERANKER_PORT:-50051}`).
- **`docker-compose.gpu.yml`** -- optional override reserving the host's NVIDIA GPU for `ollama` and `reranker`, and rebuilding `reranker`'s torch against a CUDA wheel instead of the CPU one.
- **`docker-compose.gpu-amd.yml`** -- optional override reserving the host's AMD (ROCm) GPU for `ollama` and `reranker`: swaps the Ollama image for `ollama/ollama:rocm`, passes through `/dev/kfd`/`/dev/dri`, and rebuilds `reranker`'s torch against a ROCm wheel instead of the CPU one.
- **`.env.example`** -- everything optional, including `OLLAMA_MODELS` (a comma-separated list; leave it unset and `ollama-pull` skips it and logs why), `RERANKER_MODEL` (leave it unset and the `reranker` service logs why and exits instead of starting), and `MODEL_SMOKETEST_PROMPT` (what `make smoketest` sends each model).
- **`Makefile`** -- `make up`/`up-gpu-nvidia`/`up-gpu-amd`/`down`/`down-gpu-nvidia`/`down-gpu-amd`/`clean`/`restart`/`status`/`logs`/`pull`/`smoketest` (see targets below).
- **`ollama/`** -- `entrypoint.sh` (the `ollama-pull` script, bind-mounted) and `smoketest.sh` (the `model-smoketest` script, bind-mounted).
- **`reranker/`** -- `Dockerfile` (torch build variant picked by the internal `GPU_VENDOR` build arg -- CPU wheel by default, CUDA wheel under `make up-gpu-nvidia`, ROCm wheel under `make up-gpu-amd`; nothing to configure from outside), `src/` (FastAPI app + `libs/`, including its own config loading/logging), `config.yml` (`max_length`, bind-mounted -- edit and restart, no rebuild needed).

## Environment variables

All optional -- copy `.env.example` to `.env` and uncomment/edit as needed; every var below has a working default or a no-op empty default if left unset.

| Variable | Default |
|---|---|
| `OLLAMA_MODELS` | *(unset)* |
| `OLLAMA_PORT` | `11434` |
| `RERANKER_MODEL` | `BAAI/bge-reranker-v2-m3` |
| `RERANKER_PORT` | `50051` |
| `HSA_OVERRIDE_GFX_VERSION` | `10.3.0` (`docker-compose.gpu-amd.yml` only) |
| `LOG_LEVEL` | `INFO` |
| `MODEL_SMOKETEST_PROMPT` | `Hello, who are you?` |

- **`OLLAMA_MODELS`** (used by `ollama-pull`, `model-smoketest`) -- comma-separated models to pull + warm into Ollama, e.g. `gemma3:4b,embeddinggemma:300m`. Unset means no Ollama models at all -- `ollama-pull` skips and logs why.
- **`OLLAMA_PORT`** (used by `ollama`) -- host-published port for the Ollama server.
- **`RERANKER_MODEL`** (used by `reranker`) -- cross-encoder model, pulled from Hugging Face at container startup (not build time). Unset means the `reranker` container logs why and exits instead of starting.
- **`RERANKER_PORT`** (used by `reranker`) -- host-published port for the reranker HTTP service.
- **`HSA_OVERRIDE_GFX_VERSION`** (used by `ollama`, `reranker` under `docker-compose.gpu-amd.yml`) -- makes ROCm treat the card as a different gfx target. Needed for RDNA2 mobile parts like the RX 6800M (gfx1031), which aren't on ROCm's official support list but work via the desktop gfx1030 build. Check the card's real target with `rocminfo | grep gfx` if unsure.
- **`LOG_LEVEL`** (used by `reranker`) -- Python logging level: `DEBUG`/`INFO`/`WARNING`/`ERROR`/`CRITICAL`. Ollama has its own separate logging, unaffected by this.
- **`MODEL_SMOKETEST_PROMPT`** (used by `model-smoketest`) -- prompt `make smoketest` sends to each `OLLAMA_MODELS` entry.

Not set in this project's `.env` at all, but relevant on the *consumer* project's side once this stack is up -- see [Connecting a consumer project](#connecting-a-consumer-project) below:

- **`OLLAMA_HOST`** / **`OLLAMA_PORT`** -- where the consumer project reaches this stack's Ollama.
- **`RERANKER_HOST`** / **`RERANKER_PORT`** -- where the consumer project reaches this stack's reranker.

## Connecting a consumer project

Point the consumer project at this instance via its own `.env`:

```
OLLAMA_HOST=host.docker.internal     # or this host's IP/hostname if not on the same machine
OLLAMA_PORT=11434                    # match OLLAMA_PORT above if you changed it
RERANKER_HOST=host.docker.internal
RERANKER_PORT=50051                  # match RERANKER_PORT above if you changed it
```

`host.docker.internal` resolves from inside a container back to the Docker host on Docker Desktop (Mac/Windows) out of the box; on Linux, the consumer's own compose service needs an `extra_hosts: ["host.docker.internal:host-gateway"]` entry (Docker Engine 20.10+) for that name to resolve. If this stack runs on a different machine entirely, use that host's actual IP/hostname instead.

Model names (each entry in `OLLAMA_MODELS`, plus `RERANKER_MODEL`) must match between this folder's `.env` (what gets pulled/served) and the consumer project's `.env` (what it asks for) -- there's no other link between the two.

## Testing models by hand

```bash
make smoketest
```

Sends `MODEL_SMOKETEST_PROMPT` (default `"Hello, who are you?"`) to every model in `OLLAMA_MODELS`, one at a time, and logs each reply to the terminal -- a quick "does this model actually answer sensibly" check, as opposed to `ollama-pull`'s own warm-up call, which discards the response and ignores failures. Manual and opt-in: it's gated behind Compose's `smoketest` profile, so it never runs as part of `make up`/`up-gpu-nvidia`/`up-gpu-amd`, and it exits after one pass instead of staying up. Run it whenever you want, once `ollama-pull` has finished (`docker compose logs -f ollama-pull`).

Embedding-only models (e.g. `embeddinggemma`) are expected to fail here -- they have no chat template and reject a plain prompt outright even though their real (embedding) calls work fine. A `FAILED` line for one of those isn't a problem; see `ollama/smoketest.sh`.

## Re-pulling / changing models

```bash
make pull                             # after changing OLLAMA_MODELS
docker compose up -d --build reranker # after changing RERANKER_MODEL
```

## Stopping / data

```bash
make down    # stop, keep pulled models and cached reranker weights
make clean   # stop and delete both
```

If you started with `make up-gpu-nvidia` / `make up-gpu-amd`, stop with the matching `make down-gpu-nvidia` / `make down-gpu-amd` instead of plain `make down`.

## Troubleshooting

- **Ollama model pulling is slow or seems stuck.** `docker compose logs -f ollama-pull`; exit code 0 means success. Re-run manually with `docker compose run --rm ollama-pull` if it's still missing afterwards.
- **`reranker` is slow to become healthy after a fresh start.** The model loads eagerly at container startup, not lazily on the first `/rerank` call -- `RERANKER_MODEL` downloads from Hugging Face at startup if not already cached (not at build time), which needs internet access from inside the container. Watch progress with `docker compose logs -f reranker`; subsequent restarts reuse the cached weights in the `reranker_cache` volume and start fast.
- **A consumer project can't reach Ollama or the reranker.** Confirm `OLLAMA_HOST`/`OLLAMA_PORT`/`RERANKER_HOST`/`RERANKER_PORT` in the consumer's `.env`, that this stack is actually up (`docker compose ps`), and (on Linux) that the consumer's service has the `extra_hosts` entry above if it uses `host.docker.internal`.
- **GPU isn't being used.** Confirm you started with both compose files (`-f docker-compose.yml -f docker-compose.gpu.yml`, or `make up-gpu-nvidia`; AMD is `-f docker-compose.yml -f docker-compose.gpu-amd.yml` / `make up-gpu-amd`), not just the base one -- and that you rebuilt (`--build`) after switching, since `reranker`'s torch build is picked at image-build time, not at container start. For an older NVIDIA driver that doesn't support cu121, edit the `nvidia` case in `reranker/Dockerfile` and rebuild. On AMD, confirm `/dev/kfd` and `/dev/dri` exist on the host and your user is in the `render`/`video` groups; for a card ROCm doesn't officially list (e.g. RX 6800M), check `HSA_OVERRIDE_GFX_VERSION` matches an officially-supported gfx target.
- **CPU usage seems capped / rerank calls are slower than expected.** Torch's thread count is derived automatically from the `reranker` service's `cpus:` limit in `docker-compose.yml` (see `reranker/src/libs/cpu.py`), so raising that limit is enough on its own -- see `reranker/src/libs/model.py`'s `load_model()` docstring for why torch needs to be told at all.
