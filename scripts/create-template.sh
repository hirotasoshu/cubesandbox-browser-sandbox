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
    --expose-port 10000 \
    --allow-internet-access \
    --deny-out-cidr 10.0.0.0/8 \
    --deny-out-cidr 172.16.0.0/12 \
    --deny-out-cidr 192.168.0.0/16 \
    --deny-out-cidr 169.254.0.0/16 \
    --deny-out-cidr 127.0.0.0/8 \
    --probe 9000 \
    --probe-path /cdp/json/version
