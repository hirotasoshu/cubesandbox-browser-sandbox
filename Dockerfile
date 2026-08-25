# syntax=docker/dockerfile:1.7

ARG BROWSER_BASE_IMAGE=cube-sandbox-int.tencentcloudcr.com/cube-sandbox/sandbox-browser@sha256:6d672b2e121c693aa244289bb42efc74fcc0192e8d0002afbd4dc35b81ea8ba6
FROM ${BROWSER_BASE_IMAGE}

ARG DEBIAN_FRONTEND=noninteractive
ARG PLAYWRIGHT_MCP_VERSION=0.0.79

ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    PLAYWRIGHT_MCP_CDP_ENDPOINT=http://127.0.0.1:9222

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl jq npm \
    && npm install --global --omit=dev "@playwright/mcp@${PLAYWRIGHT_MCP_VERSION}" \
    && node --version \
    && playwright-mcp --version \
    && install -d -o 1000 -g 1000 -m 775 \
       /workspace \
       /workspace/input \
       /workspace/out \
       /workspace/.harness \
    && npm cache clean --force \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY scripts/playwright-mcp-cube /usr/local/bin/playwright-mcp-cube
COPY scripts/browser-sandbox-smoke /usr/local/bin/browser-sandbox-smoke
COPY scripts/browser-sandbox-mcp-smoke /usr/local/bin/browser-sandbox-mcp-smoke
COPY scripts/mcp-http-smoke.mjs /usr/local/libexec/browser-sandbox/mcp-http-smoke.mjs

RUN chmod 755 \
    /usr/local/bin/playwright-mcp-cube \
    /usr/local/bin/browser-sandbox-smoke \
    /usr/local/bin/browser-sandbox-mcp-smoke

WORKDIR /workspace

LABEL org.opencontainers.image.source="https://github.com/hirotasoshu/cubesandbox-browser-sandbox" \
      org.opencontainers.image.description="CubeSandbox browser image with Chromium CDP and Playwright MCP"

# envd and browser CDP. Playwright MCP is intentionally stdio/local HTTP only.
EXPOSE 49983 9000
