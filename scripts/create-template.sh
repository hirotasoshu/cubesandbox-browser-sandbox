#!/usr/bin/env bash
set -euo pipefail

image="${1:-}"
alias="${2:-browser-use-runtime-medium}"

if [[ ! "${image}" =~ @sha256:[0-9a-f]{64}$ ]]; then
    printf 'Usage: %s <image@sha256:digest> [alias]\n' "$0" >&2
    exit 2
fi

cubemastercli tpl create-from-image \
    --image "${image}" \
    --alias "${alias}" \
    --cpu 2000 \
    --memory 4096 \
    --writable-layer-size 20Gi \
    --expose-port 49983 \
    --expose-port 9000 \
    --expose-port 8931 \
    --expose-port 10000 \
    --expose-port 10001 \
    --allow-internet-access \
    --probe 9000 \
    --probe-path /cdp/json/version
