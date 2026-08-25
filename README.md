# CubeSandbox Browser Runtimes

Production image contracts for `browser_use` on CubeSandbox, based on
TencentCloud's digest-pinned `sandbox-browser` image. One source tree produces
two deliberately separate targets:

- `run`: envd plus writable non-root Chromium supervisor storage and CDP ports
  `10000-10001`; the upstream headed browser/VNC stack is disabled.
- `mcp`: envd, the upstream Chromium CDP on `9000`, and an s6-managed
  `@playwright/mcp@0.0.79` HTTP service on `8931` running as UID 1000.

Both targets require a build-time `RUNTIME_MARKER` with the exact form
`sha256:<64 lowercase hex characters>`. The marker is written to
`/etc/browser-use/runtime-marker` and must match the marker promoted with the
template in `browser_use` configuration.

## Build And Verify

```bash
source_digest="$(git archive HEAD | sha256sum | cut -d' ' -f1)"
run_marker="sha256:$(printf '%s:run' "${source_digest}" | sha256sum | cut -d' ' -f1)"
mcp_marker="sha256:$(printf '%s:mcp' "${source_digest}" | sha256sum | cut -d' ' -f1)"

docker build --target run --build-arg "RUNTIME_MARKER=${run_marker}" \
  -t cubesandbox-browser-sandbox:run .
docker run -d --cap-add=SYS_ADMIN --shm-size=2g --name browser-run \
  cubesandbox-browser-sandbox:run
docker exec --user user browser-run browser-sandbox-smoke run

docker build --target mcp --build-arg "RUNTIME_MARKER=${mcp_marker}" \
  -t cubesandbox-browser-sandbox:mcp .
docker run -d --cap-add=SYS_ADMIN --shm-size=2g --name browser-mcp \
  cubesandbox-browser-sandbox:mcp
docker exec --user user browser-mcp browser-sandbox-smoke mcp
docker exec --user user browser-mcp browser-sandbox-mcp-smoke
```

`SYS_ADMIN` is only needed by the local Docker smoke so Chromium can create its
sandbox namespaces. CubeSandbox supplies the deployment isolation.

Dependencies and base images are immutable: npm packages are integrity-locked,
Python verifier dependencies are hash-locked, both build stages use image
digests, and the publish workflow emits SBOM and SLSA provenance attestations
and keyless-signs each pushed digest with Cosign. Regenerate the Python lock
with `uv pip compile requirements.in -o requirements.txt --generate-hashes`.

## Publish Outputs

The workflow publishes separate tags under
`ghcr.io/hirotasoshu/cubesandbox-browser-sandbox`:

- `run-latest`, `run-sha-<commit>`, and `run-<release tag>`;
- `mcp-latest`, `mcp-sha-<commit>`, and `mcp-<release tag>`.

Promotion must resolve a tag to its platform image digest and use only
`image@sha256:...`. Floating tags are rejected by the template script.

## Templates

Create distinct templates from published immutable digests:

```bash
scripts/create-template.sh run \
  ghcr.io/hirotasoshu/cubesandbox-browser-sandbox@sha256:<run-digest>
scripts/create-template.sh mcp \
  ghcr.io/hirotasoshu/cubesandbox-browser-sandbox@sha256:<mcp-digest>
```

The defaults are `browser-use-run-medium` and `browser-use-mcp-medium`, each
with 2 vCPU, 4 GiB RAM, and a 20 GiB writable layer. Run exposes envd and two
Run-owned CDP ports. MCP exposes envd, browser CDP, and MCP HTTP. Cube traffic
access tokens are the ingress boundary; MCP allows dynamic Cube hostnames only
because Cube validates that token before forwarding traffic.

After template creation, configure the provider's PID/process ceiling and its
mandatory private/link-local egress denial, then run the live contract before
promotion:

```bash
python -m venv .venv
.venv/bin/pip install -r requirements.txt

CUBE_RUN_TEMPLATE_ID=<run-template-id> \
CUBE_RUN_RUNTIME_MARKER=sha256:<run-marker> \
CUBE_MCP_TEMPLATE_ID=<mcp-template-id> \
CUBE_MCP_RUNTIME_MARKER=sha256:<mcp-marker> \
E2B_API_KEY=<cube-api-key> \
E2B_API_URL=<cube-api-url> \
  .venv/bin/python scripts/verify-template.py
```

The live check executes image smokes as UID 1000, verifies the marker and file
APIs, launches a Run-owned headless Chromium, proves authenticated public CDP
and MCP access, rejects missing/invalid traffic tokens, checks public navigation
and private/link-local denial, compares the exact MCP tool manifest, and invokes
the official unsafe tool confinement probe.

The final promotion authority remains the `browser_use` provider-conformance
suite. Do not enable production mode from image build success alone.

## Security

CDP and Playwright MCP grant browser control; MCP's unsafe tool is
host-RCE-equivalent. Never inject application secrets into a sandbox. Keep
traffic-token enforcement enabled, use separate Run/MCP template IDs and
markers, enforce provider PID limits, and require private/link-local denial.
