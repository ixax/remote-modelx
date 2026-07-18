#!/bin/sh
set -eu

if [ -z "${RERANKER_MODEL:-}" ]; then
    echo "reranker: RERANKER_MODEL is unset -- skipping startup"
    exit 0
fi

exec "$@"
