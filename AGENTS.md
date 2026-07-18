# AGENTS.md -- remote-modelx/

Standalone deployment, decoupled from any consumer project's own compose network -- see `README.md` for the "why" and how consumer services connect (`OLLAMA_HOST`/`OLLAMA_PORT`, `RERANKER_HOST`/`RERANKER_PORT`).

## GPU support: CPU / NVIDIA / AMD are three different paths, not one

- **CPU** -- default. `docker compose up`, no overlay.
- **NVIDIA** -- `docker-compose.nvidia.yml` overlay (`make up-gpu-nvidia`). NVIDIA's Docker GPU passthrough is mature and well-supported on both native Linux (NVIDIA Container Toolkit) and Windows (Docker Desktop's WSL2 backend has first-class CUDA-on-WSL support) -- this path is expected to just work.
- **AMD** -- no Docker overlay. Ollama runs natively on the host instead; `make up-amd` (or `pull-host`/`smoketest-host`) point the *same* `ollama-pull`/`model-smoketest` containers at it via `OLLAMA_HOST=host.docker.internal:11434` + `--no-deps`, and bring up only `reranker` (CPU-only) from Docker. See "Ollama" below.

AMD is different because, on the AMD/Windows/WSL2 combination this repo was actually developed and tested against, GPU-in-Docker turned out to be a dead end at every layer that was tried --

- Docker Desktop's WSL2 VM exposes no `/dev/kfd`/`/dev/dri` (only `/dev/dxg`, the DirectX-paravirtualization device), so the standard `ollama/ollama:rocm` image can't work there at all.
- AMD's WSL-specific ROCm path (`librocdxg`, DXCore-backed) does exist and can be made to enumerate an unsupported card (RDNA2, gfx1031) via a manual `dids.conf` entry -- but actual kernel dispatch hangs indefinitely on real hardware. Confirmed by hand: a plain HIP vector-add compiled and launched fine, then `hipDeviceSynchronize()` spun for 60+ minutes of CPU time on a sub-millisecond kernel.
- ROCm's own WSL support matrix only starts at RDNA3 (RX 7800 XT+) regardless.

On native Linux with a ROCm-supported card, AMD GPU-in-Docker generally does work (Docker's passthrough model supports it there) -- this repo just doesn't carry a maintained overlay for it, since nobody working on it could test that combination. It's a small, self-contained addition if a future contributor has that hardware (a `group_add`/`devices` block in a compose override + a build-arg case in the Dockerfile) -- see git history around the AMD-in-Docker removal for the exact shape it had (`docker-compose.gpu-amd.yml`, `GPU_VENDOR: amd` in `reranker/Dockerfile`).

## Ollama

`ollama-pull`/`model-smoketest` are plain HTTP clients against `OLLAMA_HOST` (`ollama/entrypoint.sh` / `ollama/smoketest.sh`, bind-mounted) -- they don't care whether that's the Docker `ollama` service or a host-native install, so there's one implementation for both paths, not two.

- **CPU/NVIDIA**: `OLLAMA_HOST` defaults to `ollama:11434` (the `x-vars` default in `docker-compose.yml`), the Docker `ollama` service. `make up`/`up-gpu-nvidia` start it; `ollama-pull`/`model-smoketest` `depends_on` it. `OLLAMA_KEEP_ALIVE: "-1"` on the `ollama` service (never auto-unload a loaded model) is why `entrypoint.sh` runs a throwaway `ollama run "$MODEL" "hi"` after each `pull` -- warms the model into memory once at pull time instead of eating the cold-load stall on a consumer's first real request. `docker-compose.nvidia.yml` only touches the `ollama` service's `deploy.resources.reservations` -- it's an override applied with `-f docker-compose.yml -f docker-compose.nvidia.yml`, never a replacement for the base file.
- **AMD**: Ollama installed natively on the host instead -- there's no Docker `ollama` service to point at, so `make up-amd`/`pull-host`/`smoketest-host` override `OLLAMA_HOST=host.docker.internal:11434` and pass `--no-deps` (skip the `depends_on: ollama`/`ollama-pull` chain, since that service is never started on this path). `extra_hosts: ["host.docker.internal:host-gateway"]` on both services makes `host.docker.internal` resolve on native Linux Docker Engine too, not just Docker Desktop.

## Reranker

- `reranker/src/server.py` is handlers + wiring only -- config schema, model loading, and scoring live in `reranker/src/libs/` (`config.py`, `model.py`); those functions take what they need as arguments rather than reading env/config themselves.
- `reranker/src/libs/logging_config.py` and `yaml_config.py` are this service's own config-loading/logging code, not shared with anything else in `remote-modelx/`.
- `reranker/src/libs/cpu.py` derives torch's thread count from the `reranker` service's `cpus:` cgroup quota at startup, so `docker-compose.yml`'s `cpus:` limit is the only place that number is set -- see `reranker/src/libs/model.py`'s `load_model()` docstring.
- The reranker model is loaded eagerly at import time (`server.py`), not lazily -- this service's only job is reranking, so there's no "start fast for a handshake" concern to trade off against slow startup while the checkpoint downloads.
- `reranker/Dockerfile`'s `GPU_VENDOR` build arg has `cpu` (default) and `nvidia` cases only -- no `amd` case. See "GPU support" above.
- `reranker`'s Compose service is `restart: on-failure`, not `unless-stopped` -- `entrypoint.sh` exits 0 (not a crash) when `RERANKER_MODEL` is unset, and `on-failure` won't restart-loop on a clean exit the way `unless-stopped` would.
- `reranker`'s healthcheck is a raw `/dev/tcp` check, not `curl` -- the image doesn't have curl installed.
- `reranker/Dockerfile`'s `CMD` (not baked into `ENTRYPOINT`) is what `docker-compose.yml`'s `command:` overrides -- keep them in sync if either changes. `config.yml` is copied to `/app` (not `/app/src`) because `src/server.py` reads it as a relative path resolved against uvicorn's cwd.

## Both

No env vars are read anywhere except in `docker-compose.yml`/`ollama/entrypoint.sh`/`reranker/src` themselves -- there's no other app code here to keep in sync.

## docker-compose.yml conventions

- Every env var read into `docker-compose.yml` (via `${VAR}`/`${VAR:-default}`) must be declared once as a scalar in the top-level `x-vars:` block and referenced everywhere else by YAML anchor (`&name` / `*name`), never inlined a second time in a service's `environment:`/`ports:`/etc. This keeps each var's default in exactly one place instead of risking copies drifting apart.
- Port mappings use the long `target:`/`published:` form (with `published: *anchor`), not the short `"${VAR:-default}:port"` string -- concatenating an anchor into a flow-scalar string isn't valid YAML, so the long form is the only way to keep the port anchored too.

## Shell scripts

- All `.sh` files must stay LF-terminated -- `.gitattributes` enforces `*.sh text eol=lf`. Without it, a Windows checkout with `core.autocrlf=true` rewrites them to CRLF, which breaks `exec` of the shebang line inside a Linux container (`reranker/entrypoint.sh` hit exactly this). If a `.sh` file's checked-in content ever needs touching from a Windows working copy, verify `file <path>` no longer says "with CRLF line terminators" afterwards.
