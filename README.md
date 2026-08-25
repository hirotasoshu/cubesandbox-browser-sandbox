# CubeSandbox Browser Runtime

One production image and template contract for `browser_use` on CubeSandbox,
based on TencentCloud's digest-pinned `sandbox-browser` image. Every sandbox
contains both workload capabilities:

- persistent upstream Chromium/CDP on `9000` and an s6-managed
  `@playwright/mcp@0.0.79` HTTP service on `8931`, running as UID 1000;
- writable non-root Run supervisor storage at `/run/browser-use/runs` and two
  Run-owned headless Chromium CDP slots on `10000-10001`.

The `runtime` target requires `RUNTIME_MARKER=sha256:<64 lowercase hex>`. The
marker is written to `/etc/browser-use/runtime-marker` and must match the one
promoted with the single template ID in `browser_use`.

## Build And Verify

```bash
source_digest="$(git archive HEAD | sha256sum | cut -d' ' -f1)"
marker="sha256:$(printf '%s:runtime' "${source_digest}" | sha256sum | cut -d' ' -f1)"

docker build --target runtime --build-arg "RUNTIME_MARKER=${marker}" \
  -t cubesandbox-browser-sandbox .
docker run -d --cap-add=SYS_ADMIN --shm-size=2g --name browser-runtime \
  cubesandbox-browser-sandbox
docker exec --user user browser-runtime browser-sandbox-smoke mcp
docker exec --user user browser-runtime browser-sandbox-smoke run
docker exec --user user browser-runtime browser-sandbox-mcp-smoke
```

The sequence proves that persistent MCP survives two concurrent Run-owned
Chromium processes in the same sandbox. `SYS_ADMIN` is needed only by local
Docker so Chromium can create sandbox namespaces; CubeSandbox supplies deployed
isolation.

Dependencies and base images are immutable: npm packages are integrity-locked,
Python verifier dependencies are hash-locked, both build stages use image
digests, and publishing emits SBOM and SLSA provenance attestations and
keyless-signs the pushed digest with Cosign. Regenerate the Python lock with
`uv pip compile requirements.in -o requirements.txt --generate-hashes`.

## Publish And Template

The workflow publishes `latest`, `sha-<commit>`, and release tags under
`ghcr.io/hirotasoshu/cubesandbox-browser-sandbox`. Promotion must resolve a tag
to `image@sha256:...`; floating image references are rejected:

```bash
scripts/create-template.sh \
  ghcr.io/hirotasoshu/cubesandbox-browser-sandbox@sha256:<digest>
```

The default template alias is `browser-use-runtime-medium`, with 2 vCPU, 4 GiB
RAM, and a 20 GiB writable layer. It exposes envd `49983`, persistent CDP
`9000`, MCP `8931`, and Run CDP slots `10000-10001`. Only persistent CDP is a
startup probe because Run ports are idle until a Run owns them.

Cube traffic access tokens are the ingress boundary. MCP permits dynamic Cube
hostnames only because Cube validates the token before forwarding traffic.
After template creation, configure the provider PID ceiling and mandatory
private/link-local egress denial, then run the live contract:

```bash
python -m venv .venv
.venv/bin/pip install -r requirements.txt

CUBE_TEMPLATE_ID=<template-id> \
CUBE_RUNTIME_MARKER=sha256:<runtime-marker> \
E2B_API_KEY=<cube-api-key> \
E2B_API_URL=<cube-api-url> \
  .venv/bin/python scripts/verify-template.py
```

The live check creates one secure sandbox and simultaneously verifies both
workloads: marker and file APIs, public/private network policy, authenticated
CDP on all three browser endpoints, traffic-token rejection, exact MCP tool
definitions, MCP navigation, and unsafe-tool confinement.

The final promotion authority remains the `browser_use` provider-conformance
suite. Do not enable production mode from image build success alone.

## Security

CDP and Playwright MCP grant browser control; MCP's unsafe tool is
host-RCE-equivalent. Never inject application secrets into a sandbox. Keep
traffic-token enforcement enabled, use only immutable image and marker values,
enforce provider PID limits, and require private/link-local denial.
