#!/bin/sh
# ollama-pull entrypoint -- pulls (and warms into memory) every model listed
# in OLLAMA_MODELS, a single comma-separated env var (e.g.
# "gemma3:4b,embeddinggemma:300m"). Extracted out of docker-compose.yml's
# inline `command:` so it can be edited/tested as a plain script instead of
# one-line shell glued into YAML. Bind-mounted into the ollama-pull service
# and run as its entrypoint (see docker-compose.yml).
#
# OLLAMA_MODELS is optional -- a reranker-only deployment needs no Ollama
# models at all, so an empty/unset value just skips this entirely instead of
# failing.
set -eu

if [ -z "${OLLAMA_MODELS:-}" ]; then
    echo "ollama-pull: OLLAMA_MODELS is unset -- nothing to pull"
fi

IFS=','
for model in ${OLLAMA_MODELS:-}; do
    # Trim surrounding whitespace so "gemma3:4b, embeddinggemma:300m" (a
    # space after the comma) works the same as without it.
    model=$(echo "$model" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -n "$model" ] || continue

    ollama pull "$model"
    # Load into memory now, not on the first real request -- see
    # OLLAMA_KEEP_ALIVE: "-1" on the ollama service in docker-compose.yml,
    # which then keeps it warm from here on. `ollama create`/`show` don't
    # load weights, and there's no --hidethinking-style flag for
    # embedding-only models -- a throwaway generate call is the only way to
    # warm one into memory. `|| true`: some models (embedding-only ones,
    # notably) reject a plain chat-style prompt outright even though their
    # real calls work fine, and that shouldn't fail the whole pull.
    ollama run "$model" "hi" || true
done
