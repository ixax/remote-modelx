#!/bin/sh
set -eu

PROMPT="${MODEL_SMOKETEST_PROMPT:-Hello, who are you?}"

if [ -z "${OLLAMA_MODELS:-}" ]; then
    echo "model-smoketest: OLLAMA_MODELS is unset -- nothing to test"
    exit 0
fi

IFS=','
for model in ${OLLAMA_MODELS:-}; do
    model=$(echo "$model" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -n "$model" ] || continue

    echo "---- model-smoketest: $model ----"
    echo "prompt: $PROMPT"
    if ollama run "$model" "$PROMPT"; then
        echo "model-smoketest: $model OK"
    else
        echo "model-smoketest: $model FAILED"
    fi
    echo
done

echo "model-smoketest: done"
