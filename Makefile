-include .env
export

.PHONY: up up-gpu-nvidia up-amd down down-gpu-nvidia restart status ps logs pull pull-host smoketest smoketest-host clean

up:
	docker compose up -d --build

up-gpu-nvidia:
	docker compose -f docker-compose.yml -f docker-compose.nvidia.yml up -d --build

up-amd: pull-host
	docker compose up -d --build reranker

down:
	docker compose down

down-gpu-nvidia:
	docker compose -f docker-compose.yml -f docker-compose.nvidia.yml down

clean:
	docker compose down -v

restart: down up

status ps:
	docker compose ps

logs:
	docker compose logs -f

pull:
	docker compose run --rm ollama-pull

pull-host:
	docker compose run --rm --no-deps -e OLLAMA_HOST=host.docker.internal:11434 ollama-pull

smoketest:
	docker compose --profile smoketest run --rm model-smoketest

smoketest-host:
	docker compose --profile smoketest run --rm --no-deps -e OLLAMA_HOST=host.docker.internal:11434 model-smoketest
