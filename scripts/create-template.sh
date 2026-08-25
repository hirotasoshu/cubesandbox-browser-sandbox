#!/usr/bin/env bash
set -euo pipefail

kind="${1:-}"
image="${2:-}"
alias="${3:-}"

if [[ "${kind}" != "run" && "${kind}" != "mcp" ]]; then
    printf 'Usage: %s <run|mcp> <image@sha256:digest> [alias]\n' "$0" >&2
    exit 2
fi
if [[ ! "${image}" =~ @sha256:[0-9a-f]{64}$ ]]; then
    printf 'The image must use an immutable @sha256 digest\n' >&2
    exit 2
fi

alias="${alias:-browser-use-${kind}-medium}"
ports=(--expose-port 49983)
probe=()
if [[ "${kind}" == "run" ]]; then
    ports+=(--expose-port 10000 --expose-port 10001)
else
    ports+=(--expose-port 9000 --expose-port 8931)
    probe=(--probe 9000 --probe-path /cdp/json/version)
fi

cubemastercli tpl create-from-image \
    --image "${image}" \
    --alias "${alias}" \
    --cpu 2000 \
    --memory 4096 \
    --writable-layer-size 20Gi \
    "${ports[@]}" \
    --allow-internet-access \
    "${probe[@]}"
