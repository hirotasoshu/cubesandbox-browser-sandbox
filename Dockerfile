# syntax=docker/dockerfile:1.7

ARG NODE_IMAGE=node:20.19.2-bookworm-slim@sha256:7cd3fbc830c75c92256fe1122002add9a1c025831af8770cd0bf8e45688ef661
ARG BROWSER_BASE_IMAGE=cube-sandbox-int.tencentcloudcr.com/cube-sandbox/sandbox-browser@sha256:6d672b2e121c693aa244289bb42efc74fcc0192e8d0002afbd4dc35b81ea8ba6
FROM ${NODE_IMAGE} AS playwright-mcp-dependencies

WORKDIR /opt/playwright-mcp
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts \
    && npm cache clean --force

FROM ${BROWSER_BASE_IMAGE} AS common

USER root

COPY scripts/browser-sandbox-smoke /usr/local/bin/browser-sandbox-smoke
RUN install -d -o user -g user -m 0775 \
        /workspace \
        /workspace/input \
        /workspace/out \
        /workspace/.harness \
    && chmod 0755 /usr/local/bin/browser-sandbox-smoke

WORKDIR /workspace

LABEL org.opencontainers.image.source="https://github.com/hirotasoshu/cubesandbox-browser-sandbox"

FROM common AS run
ARG RUNTIME_MARKER
RUN test "${#RUNTIME_MARKER}" -eq 71 \
    && test "${RUNTIME_MARKER#sha256:}" != "${RUNTIME_MARKER}" \
    && case "${RUNTIME_MARKER#sha256:}" in *[!0-9a-f]*) exit 1 ;; esac \
    && install -d -m 0755 /etc/browser-use \
    && printf '%s\n' "${RUNTIME_MARKER}" > /etc/browser-use/runtime-marker \
    && install -d -o user -g user -m 0700 /run/browser-use/runs \
    && rm -f \
        /etc/s6-overlay/s6-rc.d/user/contents.d/chromium \
        /etc/s6-overlay/s6-rc.d/user/contents.d/nginx \
        /etc/s6-overlay/s6-rc.d/user/contents.d/novnc \
        /etc/s6-overlay/s6-rc.d/user/contents.d/x11vnc \
        /etc/s6-overlay/s6-rc.d/user/contents.d/xvfb
LABEL org.opencontainers.image.title="CubeSandbox browser-use Run runtime" \
    org.opencontainers.image.description="Non-root Chromium supervisor runtime for browser-use runs" \
    org.opencontainers.image.revision-marker="${RUNTIME_MARKER}"
EXPOSE 49983 10000 10001

FROM common AS mcp
ARG RUNTIME_MARKER
ENV PATH="/opt/playwright-mcp/node_modules/.bin:${PATH}" \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    PLAYWRIGHT_MCP_CDP_ENDPOINT=http://127.0.0.1:9222
COPY --from=playwright-mcp-dependencies /opt/playwright-mcp /opt/playwright-mcp
COPY scripts/playwright-mcp-cube /usr/local/bin/playwright-mcp-cube
COPY scripts/browser-sandbox-mcp-smoke /usr/local/bin/browser-sandbox-mcp-smoke
COPY scripts/playwright-mcp-service-run /usr/local/libexec/browser-sandbox/playwright-mcp-service-run
COPY scripts/mcp-http-smoke.mjs /usr/local/libexec/browser-sandbox/mcp-http-smoke.mjs
RUN test "${#RUNTIME_MARKER}" -eq 71 \
    && test "${RUNTIME_MARKER#sha256:}" != "${RUNTIME_MARKER}" \
    && case "${RUNTIME_MARKER#sha256:}" in *[!0-9a-f]*) exit 1 ;; esac \
    && install -d -m 0755 /etc/browser-use \
    && printf '%s\n' "${RUNTIME_MARKER}" > /etc/browser-use/runtime-marker \
    && install -d \
        /etc/s6-overlay/s6-rc.d/playwright-mcp/dependencies.d \
        /etc/s6-overlay/s6-rc.d/user/contents.d \
    && printf 'longrun\n' > /etc/s6-overlay/s6-rc.d/playwright-mcp/type \
    && touch /etc/s6-overlay/s6-rc.d/playwright-mcp/dependencies.d/chromium \
    && ln -s /usr/local/libexec/browser-sandbox/playwright-mcp-service-run \
        /etc/s6-overlay/s6-rc.d/playwright-mcp/run \
    && touch /etc/s6-overlay/s6-rc.d/user/contents.d/playwright-mcp \
    && chmod 0755 \
        /usr/local/bin/playwright-mcp-cube \
        /usr/local/bin/browser-sandbox-mcp-smoke \
        /usr/local/libexec/browser-sandbox/playwright-mcp-service-run \
        /usr/local/libexec/browser-sandbox/mcp-http-smoke.mjs
LABEL org.opencontainers.image.title="CubeSandbox browser-use MCP runtime" \
    org.opencontainers.image.description="Persistent non-root Playwright MCP runtime for browser-use" \
    org.opencontainers.image.revision-marker="${RUNTIME_MARKER}"
EXPOSE 49983 9000 8931
