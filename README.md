# remote-modelx

A standalone deployment of [Ollama](https://ollama.com/) and a cross-encoder reranking HTTP service, meant to run together and be copied into another project wholesale. Not on the same Docker network as any consumer project -- consumer services reach these over the host (`OLLAMA_HOST`/`OLLAMA_PORT`, `RERANKER_HOST`/`RERANKER_PORT` in the consumer's own `.env`), not via container-name DNS.

## Quick start

```bash
cp .env.example .env   # set OLLAMA_MODELS, e.g. "gemma3:4b,bge-m3", if you need Ollama models; RERANKER_MODEL, e.g. "BAAI/bge-reranker-v2-m3", if you need reranking
```

Pick the path that matches your GPU (see [AGENTS.md](AGENTS.md) for why AMD is different):

**CPU (default, no GPU or GPU not reachable from Docker):**

```bash
make up
docker compose logs -f ollama-pull   # watch the Ollama model pull -- can take minutes
docker compose logs -f reranker      # watch it download + load RERANKER_MODEL on startup
```

**NVIDIA GPU:** requires an NVIDIA GPU reachable from Docker -- on Windows that's Docker Desktop with the WSL2 backend plus the NVIDIA driver on the Windows host (provides CUDA support inside WSL2 itself, no separate driver install inside WSL/the container); on Linux, the NVIDIA Container Toolkit. Not applicable on macOS -- Docker Desktop there has no GPU passthrough path into containers.

```bash
make up-gpu-nvidia
```

**AMD GPU:** GPU-in-Docker doesn't work for AMD here (WSL2 lacks the device nodes ROCm needs, and even AMD's WSL-specific DXCore path hangs on real dispatch -- see AGENTS.md for the full story). Install [Ollama](https://ollama.com/download) natively on the host instead, then:

```bash
make up-amd
```

`up-amd` runs `ollama-pull` in a container pointed at the host's native Ollama (`OLLAMA_HOST=host.docker.internal:11434`, `--no-deps` so it doesn't also try to start the `ollama` container) to pull + warm `OLLAMA_MODELS`, then brings up `reranker` here CPU-only. Don't run plain `make up`/`docker compose up` on this path -- it would start a second, empty `ollama` container fighting the native one for port `11434`.

No `make` available (e.g. plain PowerShell on Windows)? Run its two steps directly:

```powershell
docker compose run --rm --no-deps -e OLLAMA_HOST=host.docker.internal:11434 ollama-pull
docker compose up -d --build reranker
```

On any path, once everything's up, optionally sanity-check the Ollama models by hand:

```bash
make smoketest        # CPU/NVIDIA
make smoketest-host    # AMD
```

## What's here

- **`docker-compose.yml`** -- `ollama` (server, port `${OLLAMA_PORT:-11434}`), `ollama-pull` (one-shot job that pulls + warms every model in `OLLAMA_MODELS` into whatever `OLLAMA_HOST` points at), `model-smoketest` (manual, opt-in -- see below), and `reranker` (cross-encoder HTTP service, port `${RERANKER_PORT:-50051}`). On the AMD path, only `reranker` and one-off `ollama-pull`/`model-smoketest` runs (via `--no-deps`) from this file are ever used -- the long-running `ollama` service isn't.
- **`docker-compose.nvidia.yml`** -- optional override reserving the host's NVIDIA GPU for `ollama` and `reranker`, and rebuilding `reranker`'s torch against a CUDA wheel instead of the CPU one. No AMD equivalent -- see AGENTS.md.
- **`.env.example`** -- everything optional, including `OLLAMA_MODELS` (a comma-separated list; leave it unset and `ollama-pull` skips it and logs why), `RERANKER_MODEL` (leave it unset and the `reranker` service logs why and exits instead of starting), and `MODEL_SMOKETEST_PROMPT` (what `make smoketest`/`smoketest-host` send each model).
- **`Makefile`** -- `make up`/`up-gpu-nvidia`/`up-amd`/`down`/`down-gpu-nvidia`/`clean`/`restart`/`status`/`logs`/`pull`/`pull-host`/`smoketest`/`smoketest-host` (see targets below). The `-host` targets are the AMD path -- same `ollama-pull`/`model-smoketest` services, pointed at the host's native Ollama instead of the Docker one.
- **`ollama/`** -- `entrypoint.sh` (the `ollama-pull` script, bind-mounted) and `smoketest.sh` (the `model-smoketest` script, bind-mounted). Both just talk to `OLLAMA_HOST` over HTTP -- used on every path, Docker-hosted or host-native.
- **`reranker/`** -- `Dockerfile` (torch build variant picked by the internal `GPU_VENDOR` build arg -- CPU wheel by default, CUDA wheel under `make up-gpu-nvidia`; no AMD case, see AGENTS.md), `src/` (FastAPI app + `libs/`, including its own config loading/logging), `config.yml` (`max_length`, bind-mounted -- edit and restart, no rebuild needed).

## Environment variables

All optional -- copy `.env.example` to `.env` and uncomment/edit as needed; every var below has a working default or a no-op empty default if left unset.

### Ollama

| Variable | Default | Description |
|---|---|---|
| `OLLAMA_MODELS` | *(unset)* | Comma-separated models to pull + warm into Ollama, e.g. `gemma3:12b,bge-m3`. Read by `ollama-pull`/`model-smoketest`. Unset means no Ollama models at all. |
| `OLLAMA_PORT` | `11434` | Host-published port for the Docker `ollama` service. CPU/NVIDIA only -- ignored on AMD (`make up-amd`/`*-host` targets hardcode `host.docker.internal:11434` instead, Ollama's own default port). |
| `OLLAMA_HOST` | `ollama:11434` | Internal, not in `.env.example` -- where `ollama-pull`/`model-smoketest` point the `ollama` CLI, in Ollama's own `host:port` format (not the bare-host `OLLAMA_HOST` below under "Consumer project", which is this repo's own, unrelated convention for a different `.env`). The `-host` Makefile targets override it via `-e`, not `.env`. |

### Reranker

| Variable | Default | Description |
|---|---|---|
| `RERANKER_MODEL` | *(unset)* | Cross-encoder model, pulled from Hugging Face at container startup (not build time), e.g. `BAAI/bge-reranker-v2-m3`. Unset means the `reranker` container logs why and exits instead of starting. |
| `RERANKER_PORT` | `50051` | Host-published port for the reranker HTTP service. |
| `LOG_LEVEL` | `INFO` | Python logging level: `DEBUG`/`INFO`/`WARNING`/`ERROR`/`CRITICAL`. Ollama has its own separate logging, unaffected by this. |

### Testing

| Variable | Default | Description |
|---|---|---|
| `MODEL_SMOKETEST_PROMPT` | `Hello, who are you?` | Prompt sent to each `OLLAMA_MODELS` entry (`make smoketest`/`smoketest-host`) to confirm it actually answers, not just that it loaded. |

### Consumer project

Not set in this project's `.env` at all -- set on the *consumer* project's side once this stack is up, see [Connecting a consumer project](#connecting-a-consumer-project) below. This `OLLAMA_HOST` is a bare host, unlike the `host:port` one under "Ollama" above -- different variable, different `.env` file, same name by coincidence.

| Variable | Description |
|---|---|
| `OLLAMA_HOST` / `OLLAMA_PORT` | Where the consumer project reaches this stack's Ollama. |
| `RERANKER_HOST` / `RERANKER_PORT` | Where the consumer project reaches this stack's reranker. |

## Connecting a consumer project

`OLLAMA_HOST`/`OLLAMA_PORT`/`RERANKER_HOST`/`RERANKER_PORT` in the consumer's own `.env`, pointed at this host (`host.docker.internal` from a container on the same machine via Docker Desktop, or `extra_hosts: ["host.docker.internal:host-gateway"]` on Linux; that host's actual IP/hostname if remote). This convention is specific to this stack's original companion project (mcp-server), not a generic protocol -- a different consumer reads config its own way.

## Reranker API

```
POST /rerank
{"query": "...", "documents": ["...", "..."]}

-> {"scores": [0.03, 0.00002], "model": "BAAI/bge-reranker-v2-m3", "duration_ms": 412.0}
```

`scores` is aligned 1:1 with `documents`, in request order (not sorted) -- the caller sorts/truncates as needed.

## Testing models by hand

```bash
make smoketest        # CPU/NVIDIA
make smoketest-host   # AMD
```

Sends `MODEL_SMOKETEST_PROMPT` (default `"Hello, who are you?"`) to every model in `OLLAMA_MODELS`, one at a time, and logs each reply to the terminal -- a quick "does this model actually answer sensibly" check, as opposed to `ollama-pull`'s own warm-up call, which discards the response and ignores failures. Manual and opt-in: gated behind Compose's `smoketest` profile, so it never runs as part of `make up`/`up-gpu-nvidia`/`up-amd`, and it exits after one pass instead of staying up.

Embedding-only models (e.g. `bge-m3`) may fail this depending on your Ollama version -- some reject a plain chat-style prompt outright (no chat template) even though their real (embedding) calls work fine, others return the raw embedding vector instead of erroring. Either way, a `FAILED` line for one of those isn't necessarily a problem; see `ollama/smoketest.sh`.

## Re-pulling / changing models

```bash
make pull                             # CPU/NVIDIA, after changing OLLAMA_MODELS
make pull-host                        # AMD, after changing OLLAMA_MODELS
docker compose up -d --build reranker # after changing RERANKER_MODEL, any path
```

## Stopping / data

```bash
make down    # CPU/NVIDIA -- stop, keep pulled models and cached reranker weights
make clean   # CPU/NVIDIA -- stop and delete both
```

If you started with `make up-gpu-nvidia`, stop with `make down-gpu-nvidia` instead of plain `make down`. On AMD, `docker compose down`/`docker compose down -v` stop just `reranker` (Ollama's own models live in Ollama's own data directory on the host, unaffected -- manage those with `ollama rm <model>` etc).

## Troubleshooting

- **Ollama model pulling is slow or seems stuck.** `docker compose logs -f ollama-pull` (CPU/NVIDIA); exit code 0 means success. Re-run with `make pull`/`pull-host` if it's still missing afterwards.
- **`reranker` is slow to become healthy after a fresh start.** The model loads eagerly at container startup, not lazily on the first `/rerank` call -- `RERANKER_MODEL` downloads from Hugging Face at startup if not already cached (not at build time), which needs internet access from inside the container. Watch progress with `docker compose logs -f reranker`; subsequent restarts reuse the cached weights in the `reranker_cache` volume and start fast.
- **A consumer project can't reach Ollama or the reranker.** Confirm `OLLAMA_HOST`/`OLLAMA_PORT`/`RERANKER_HOST`/`RERANKER_PORT` in the consumer's `.env`, that this stack is actually up (`docker compose ps` for CPU/NVIDIA; `docker compose ps` + `ollama list` for AMD), and (on Linux) that the consumer's service has the `extra_hosts` entry above if it uses `host.docker.internal`.
- **NVIDIA GPU isn't being used.** Confirm you started with both compose files (`-f docker-compose.yml -f docker-compose.nvidia.yml`, or `make up-gpu-nvidia`), not just the base one -- and that you rebuilt (`--build`) after switching, since `reranker`'s torch build is picked at image-build time, not at container start. For an older NVIDIA driver that doesn't support cu121, edit the `nvidia` case in `reranker/Dockerfile` and rebuild.
- **AMD: is GPU-in-Docker really not possible for me?** If you're on native Linux with a ROCm-supported card, GPU-in-Docker generally does work (this repo just doesn't ship an overlay for it anymore -- see AGENTS.md for why it isn't maintained here, and git history before that note for the shape it used to have). If you're on Windows/WSL2, it isn't -- confirmed by hand against real hardware, see AGENTS.md.
- **CPU usage seems capped / rerank calls are slower than expected.** Torch's thread count is derived automatically from the `reranker` service's `cpus:` limit in `docker-compose.yml` (see `reranker/src/libs/cpu.py`), so raising that limit is enough on its own -- see `reranker/src/libs/model.py`'s `load_model()` docstring for why torch needs to be told at all.
- **Need the reranker reachable from another machine on the LAN.** Docker already publishes it on all host interfaces (`0.0.0.0:${RERANKER_PORT}`); the host firewall is what's actually blocking it by default. On Windows: `New-NetFirewallRule -DisplayName "reranker" -Direction Inbound -Protocol TCP -LocalPort 50051 -Action Allow -Profile Private` (requires an elevated PowerShell, and the network must actually be categorized Private -- check with `Get-NetConnectionProfile`).
