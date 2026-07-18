#!/bin/bash
set -eu

PROMPT="${MODEL_SMOKETEST_PROMPT:-Hello, who are you?}"
RERANKER_HOST="${RERANKER_HOST:-reranker}"
RERANKER_PORT="${RERANKER_PORT:-50051}"

echo "==== ollama ===="
if [ -z "${OLLAMA_MODELS:-}" ]; then
    echo "model-smoketest: OLLAMA_MODELS is unset -- nothing to test"
else
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
fi

echo "==== reranker ===="
if [ -z "${RERANKER_MODEL:-}" ]; then
    echo "model-smoketest: RERANKER_MODEL is unset -- skipping reranker"
else
    echo "---- model-smoketest: reranker ($RERANKER_MODEL @ $RERANKER_HOST:$RERANKER_PORT) ----"
    body='{"query":"ping","texts":["ping","pong"]}'
    request=$(printf 'POST /rerank HTTP/1.1\r\nHost: %s\r\nContent-Type: application/json\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' \
        "$RERANKER_HOST" "${#body}" "$body")

    # No curl/wget in this image (ollama/ollama:latest) -- same raw /dev/tcp
    # approach as reranker's own Compose healthcheck, just with a real
    # POST /rerank body instead of a bare connect check, since we want to
    # confirm the service actually answers, not just that the port is open.
    response=$(timeout 10 bash -c "exec 3<>/dev/tcp/${RERANKER_HOST}/${RERANKER_PORT}; printf '%s' \"\$1\" >&3; cat <&3" _ "$request" 2>/dev/null || true)

    if echo "$response" | grep -q '"index"'; then
        echo "$response"
        echo "model-smoketest: reranker OK"
    else
        echo "model-smoketest: reranker FAILED (is the reranker container up and healthy?)"
    fi
fi

echo "model-smoketest: done"
