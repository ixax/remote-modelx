-include .env
export

.PHONY: up up-gpu-nvidia up-gpu-amd down down-gpu-nvidia down-gpu-amd restart status ps logs pull smoketest clean

up:
	docker compose up -d --build

up-gpu-nvidia:
	docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d --build

up-gpu-amd:
	docker compose -f docker-compose.yml -f docker-compose.gpu-amd.yml up -d --build

down:
	docker compose down

down-gpu-nvidia:
	docker compose -f docker-compose.yml -f docker-compose.gpu.yml down

down-gpu-amd:
	docker compose -f docker-compose.yml -f docker-compose.gpu-amd.yml down

clean:
	docker compose down -v

restart: down up

status ps:
	docker compose ps

logs:
	docker compose logs -f

pull:
	docker compose run --rm ollama-pull

smoketest:
	docker compose --profile smoketest run --rm model-smoketest
