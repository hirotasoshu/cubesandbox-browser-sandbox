#!/usr/bin/env bash
set -euo pipefail

image="${1:-ghcr.io/hirotasoshu/cubesandbox-browser-sandbox:latest}"
alias="${2:-browser-sandbox-medium}"

cubemastercli tpl create-from-image \
    --image "${image}" \
    --alias "${alias}" \
    --cpu 2000 \
    --memory 4096 \
    --writable-layer-size 20Gi \
    --expose-port 49983 \
    --expose-port 9000 \
    --allow-internet-access \
    --probe 9000 \
    --probe-path /cdp/json/version
