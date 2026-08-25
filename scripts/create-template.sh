#!/usr/bin/env bash
set -euo pipefail

image="${1:-ghcr.io/hirotasoshu/cubesandbox-browser-sandbox@sha256:3eecbacef8ba527ed6140c77b4e543db67641b6b05f4112bb70067bf75b8bde8}"
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
