#!/bin/sh
set -eu

if [ -z "${OLLAMA_MODELS:-}" ]; then
    echo "ollama-pull: OLLAMA_MODELS is unset -- nothing to pull"
fi

IFS=','
for model in ${OLLAMA_MODELS:-}; do
    model=$(echo "$model" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -n "$model" ] || continue

    ollama pull "$model"
    ollama run "$model" "hi" || true
done
