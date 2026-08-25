# CubeSandbox Browser Sandbox

Browser-focused CubeSandbox image based on TencentCloud's official
`sandbox-browser` image. It provides:

- Chromium with Xvfb, controlled over CDP through port `9000`;
- CubeSandbox `envd` on port `49983`;
- pinned `@playwright/mcp` with a wrapper that connects to the existing browser;
- a writable `/workspace` for UID 1000;
- local and live template smoke tests.

The upstream browser example is documented at
[`TencentCloud/CubeSandbox/examples/browser-sandbox`](https://github.com/TencentCloud/CubeSandbox/tree/master/examples/browser-sandbox).

## Image

```text
ghcr.io/hirotasoshu/cubesandbox-browser-sandbox:latest
```

Versions are pinned in `Dockerfile`, including the upstream image digest and
Playwright MCP version.

## Build

```bash
docker build -t cubesandbox-browser-sandbox .
docker run --rm --cap-add=SYS_ADMIN --shm-size=2g \
  cubesandbox-browser-sandbox browser-sandbox-smoke
```

The runtime smoke requires the normal image entrypoint because it checks the
running Chromium CDP endpoint. `SYS_ADMIN` lets Chromium create its sandbox
namespaces under Docker; the CubeSandbox runtime provides the corresponding
isolation in deployed sandboxes.

## Template

Create the medium profile with 2 vCPU, 4 GiB RAM, and a 20 GiB writable layer:

```bash
scripts/create-template.sh
```

The template exposes `49983` for envd and `9000` for browser CDP. Playwright
MCP is deliberately not exposed publicly; agents run it inside the sandbox via
stdio or a loopback HTTP transport.

## Remote Playwright

```bash
python -m venv .venv
.venv/bin/pip install -r requirements.txt
cp .env.example .env
.venv/bin/python examples/browser.py
```

The example creates a sandbox, reads the debugger URL from
`https://<sandbox-host>:9000/cdp/json/version`, upgrades its public scheme to
`wss://`, opens `https://example.com`, and prints `Example Domain`.

## Playwright MCP

Inside a sandbox, configure an MCP client to run:

```text
playwright-mcp-cube
```

The wrapper injects:

```text
--cdp-endpoint http://127.0.0.1:9222
```

so MCP reuses the Chromium process managed by the image instead of downloading
or launching a second browser. Ready-to-copy configurations are in
`mcp-configs/`.

For a standalone loopback MCP endpoint:

```bash
playwright-mcp-cube --port 8931 --host 127.0.0.1 --shared-browser-context
```

## Verification

With Cube API variables configured:

```bash
CUBE_TEMPLATE_ID=browser-sandbox-medium .venv/bin/python scripts/verify-template.py
```

The verification checks envd, browser readiness, remote CDP navigation, MCP
initialization, MCP tool discovery, and an MCP-driven navigation to
`https://example.com`.

## Security

CDP grants full control over the browser. Playwright MCP is not a security
boundary. Keep MCP on stdio or loopback and use CubeSandbox traffic-token
protection when CDP is reachable by untrusted clients.
