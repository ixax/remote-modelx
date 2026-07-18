#!/bin/sh
# model-smoketest entrypoint -- sends a fixed prompt to every model in
# OLLAMA_MODELS, one at a time, and logs the reply so a human can eyeball
# that each one actually answers sensibly. Different job than ollama-pull's
# own warm-up call (which discards output and swallows failures with
# `|| true` -- see ollama/entrypoint.sh): that one just gets weights into
# memory, this one is for a person to read.
#
# Manual/opt-in only -- gated behind the `smoketest` Compose profile (see
# docker-compose.yml), not part of `make up`. Run with `make smoketest`.
set -eu

PROMPT="${MODEL_SMOKETEST_PROMPT:-Hello, who are you?}"

if [ -z "${OLLAMA_MODELS:-}" ]; then
    echo "model-smoketest: OLLAMA_MODELS is unset -- nothing to test"
    exit 0
fi

IFS=','
for model in ${OLLAMA_MODELS:-}; do
    # Trim surrounding whitespace, same as ollama-pull's own loop.
    model=$(echo "$model" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -n "$model" ] || continue

    echo "---- model-smoketest: $model ----"
    echo "prompt: $PROMPT"
    # Not `|| true` here, unlike ollama-pull -- a rejected prompt is exactly
    # what this is meant to surface (e.g. embedding-only models, which have
    # no chat template and error out on a plain prompt). Still continue to
    # the next model either way.
    if ollama run "$model" "$PROMPT"; then
        echo "model-smoketest: $model OK"
    else
        echo "model-smoketest: $model FAILED"
    fi
    echo
done

echo "model-smoketest: done"
