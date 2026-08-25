#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from e2b import Sandbox
from playwright.sync_api import sync_playwright


ROOT = Path(__file__).resolve().parent.parent
TRAFFIC_HEADER = "e2b-traffic-access-token"


def create_sandbox(template_id: str) -> Sandbox:
    return Sandbox.create(
        template=template_id,
        timeout=300,
        envs={},
        secure=True,
        allow_internet_access=True,
        network={"allow_public_traffic": False},
    )


def traffic_request(url: str, token: str) -> Request:
    return Request(url, headers={TRAFFIC_HEADER: token})


def traffic_token(sandbox: Sandbox) -> str:
    token = sandbox.traffic_access_token
    if not token:
        raise RuntimeError("Cube did not issue a traffic access token")
    return token


def require_denied(url: str, token: str | None) -> None:
    headers = {} if token is None else {TRAFFIC_HEADER: token}
    try:
        with urlopen(Request(url, headers=headers), timeout=10):
            pass
    except HTTPError as error:
        if error.code == 403:
            return
        raise RuntimeError(
            f"Unexpected ingress rejection status: {error.code}"
        ) from error
    except URLError as error:
        raise RuntimeError("Ingress token probe could not reach Cube") from error
    raise RuntimeError(f"Unauthenticated ingress was accepted: {url}")


def require_mcp_token_rejected(url: str, token: str | None) -> None:
    headers = {
        "accept": "application/json, text/event-stream",
        "content-type": "application/json",
    }
    if token is not None:
        headers[TRAFFIC_HEADER] = token
    request = Request(
        url,
        data=json.dumps(
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": "2025-03-26",
                    "capabilities": {},
                    "clientInfo": {"name": "token-probe", "version": "1"},
                },
            }
        ).encode(),
        headers=headers,
        method="POST",
    )
    try:
        with urlopen(request, timeout=10):
            pass
    except HTTPError as error:
        if error.code == 403:
            return
        raise RuntimeError(f"Unexpected MCP rejection status: {error.code}") from error
    except URLError as error:
        raise RuntimeError("MCP token probe could not reach Cube") from error
    raise RuntimeError("MCP ingress accepted a missing or invalid traffic token")


def run_command(sandbox: Sandbox, command: str, timeout: int = 180) -> None:
    result = sandbox.commands.run(command, user="user", timeout=timeout)
    print(result.stdout, end="")
    if result.exit_code != 0:
        print(result.stderr, end="")
        raise RuntimeError(f"Sandbox command failed: {command}")


def verify_marker(sandbox: Sandbox, expected_marker: str) -> None:
    result = sandbox.commands.run(
        "cat /etc/browser-use/runtime-marker", user="user", timeout=30
    )
    if result.exit_code != 0 or result.stdout.strip() != expected_marker:
        raise RuntimeError("Sandbox runtime marker does not match the promotion marker")


def verify_network_policy(sandbox: Sandbox) -> None:
    script = """
import json
import urllib.request

def probe(url):
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            return 200 <= response.status < 500
    except Exception:
        return False

print(json.dumps({
    "public": probe("https://example.com/"),
    "private": probe("http://10.255.255.1/"),
    "link_local": probe("http://169.254.169.254/latest/meta-data/"),
}))
"""
    result = sandbox.commands.run(
        "python3 - <<'PY'\n" + script + "PY", user="user", timeout=30
    )
    observed = json.loads(result.stdout.strip())
    expected = {"public": True, "private": False, "link_local": False}
    if result.exit_code != 0 or observed != expected:
        raise RuntimeError(f"Unexpected sandbox network policy: {observed}")


def verify_token(sandbox: Sandbox, port: int, path: str) -> str:
    host = sandbox.get_host(port)
    url = f"https://{host}{path}"
    token = traffic_token(sandbox)
    with urlopen(traffic_request(url, token), timeout=30) as response:
        if response.status >= 400:
            raise RuntimeError(f"Authenticated ingress failed: {response.status}")
    require_denied(url, None)
    require_denied(url, f"{token}-invalid")
    return url


def verify_run(template_id: str, expected_marker: str) -> None:
    with create_sandbox(template_id) as sandbox:
        run_command(sandbox, "browser-sandbox-smoke run")
        verify_marker(sandbox, expected_marker)
        verify_network_policy(sandbox)
        sandbox.files.write("/workspace/input/provider-contract.txt", "cube-ok")
        if sandbox.files.read("/workspace/input/provider-contract.txt") != "cube-ok":
            raise RuntimeError("Sandbox file round trip failed")

        run_command(
            sandbox,
            "mkdir -p /run/browser-use/runs/provider-contract/profiles",
        )
        processes = []
        for index in range(2):
            port = 10000 + index
            processes.append(
                sandbox.commands.run(
                    "exec chromium --no-first-run --no-default-browser-check "
                    "--disable-dev-shm-usage "
                    "--remote-debugging-address=127.0.0.1 "
                    f"--remote-debugging-port={port} "
                    "--user-data-dir="
                    f"/run/browser-use/runs/provider-contract/profiles/{index} "
                    "--headless=new about:blank",
                    user="user",
                    background=True,
                )
            )
        try:
            token = traffic_token(sandbox)
            with sync_playwright() as playwright:
                for index in range(2):
                    port = 10000 + index
                    cdp_url = f"https://{sandbox.get_host(port)}/json/version"
                    for _ in range(60):
                        try:
                            with urlopen(
                                traffic_request(cdp_url, token), timeout=2
                            ) as response:
                                debugger_url = json.load(response)[
                                    "webSocketDebuggerUrl"
                                ]
                            break
                        except (HTTPError, URLError, KeyError):
                            time.sleep(0.5)
                    else:
                        raise RuntimeError(
                            f"Run Chromium CDP did not become ready: {port}"
                        )

                    require_denied(cdp_url, None)
                    require_denied(cdp_url, f"{token}-invalid")
                    browser = playwright.chromium.connect_over_cdp(
                        debugger_url,
                        headers={TRAFFIC_HEADER: token},
                    )
                    page = browser.contexts[0].new_page()
                    page.goto("https://example.com", wait_until="domcontentloaded")
                    if page.title() != "Example Domain":
                        raise RuntimeError(f"Unexpected page title: {page.title()!r}")
                    browser.close()
            print("RUN_TEMPLATE_OK")
        finally:
            for process in reversed(processes):
                process.kill()


def verify_mcp(template_id: str, expected_marker: str) -> None:
    with create_sandbox(template_id) as sandbox:
        run_command(sandbox, "browser-sandbox-smoke mcp")
        verify_marker(sandbox, expected_marker)
        verify_network_policy(sandbox)
        run_command(sandbox, "browser-sandbox-mcp-smoke")
        verify_token(sandbox, 9000, "/cdp/json/version")
        endpoint = f"https://{sandbox.get_host(8931)}/mcp"
        token = traffic_token(sandbox)
        require_mcp_token_rejected(endpoint, None)
        require_mcp_token_rejected(endpoint, f"{token}-invalid")
        environment = os.environ.copy()
        environment["E2B_TRAFFIC_ACCESS_TOKEN"] = token
        subprocess.run(
            ["node", str(ROOT / "scripts/mcp-http-smoke.mjs"), endpoint],
            check=True,
            env=environment,
        )
        print("MCP_TEMPLATE_OK")


def main() -> None:
    run_template = os.environ.get("CUBE_RUN_TEMPLATE_ID")
    mcp_template = os.environ.get("CUBE_MCP_TEMPLATE_ID")
    if not run_template and not mcp_template:
        raise SystemExit("Set CUBE_RUN_TEMPLATE_ID and/or CUBE_MCP_TEMPLATE_ID")
    if run_template:
        run_marker = os.environ.get("CUBE_RUN_RUNTIME_MARKER")
        if not run_marker:
            raise SystemExit("Set CUBE_RUN_RUNTIME_MARKER")
        verify_run(run_template, run_marker)
    if mcp_template:
        mcp_marker = os.environ.get("CUBE_MCP_RUNTIME_MARKER")
        if not mcp_marker:
            raise SystemExit("Set CUBE_MCP_RUNTIME_MARKER")
        verify_mcp(mcp_template, mcp_marker)


if __name__ == "__main__":
    main()
