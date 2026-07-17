#!/bin/sh
# reranker entrypoint -- RERANKER_MODEL has no usable default (there's no
# "off" cross-encoder), so a consumer project that doesn't need reranking
# leaves it unset. Rather than crash-looping on a required env var, log why
# and exit 0 so the container reports as stopped, not failed.
set -eu

if [ -z "${RERANKER_MODEL:-}" ]; then
    echo "reranker: RERANKER_MODEL is unset -- skipping startup"
    exit 0
fi

exec "$@"
