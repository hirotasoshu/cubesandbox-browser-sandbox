#!/usr/bin/env python3
from __future__ import annotations

import os

from e2b import Sandbox
from playwright.sync_api import sync_playwright


template_id = os.environ["CUBE_TEMPLATE_ID"]

with Sandbox.create(template=template_id, timeout=300) as sandbox:
    smoke = sandbox.commands.run("browser-sandbox-smoke", user="root", timeout=120)
    print(smoke.stdout, end="")
    if smoke.exit_code != 0:
        print(smoke.stderr, end="")
        raise SystemExit(smoke.exit_code)

    cdp_url = f"https://{sandbox.get_host(9000)}/cdp?"
    with sync_playwright() as playwright:
        browser = playwright.chromium.connect_over_cdp(cdp_url)
        context = browser.new_context(ignore_https_errors=True)
        page = context.new_page()
        page.goto("https://example.com", wait_until="domcontentloaded")
        if page.title() != "Example Domain":
            raise RuntimeError(f"Unexpected page title: {page.title()!r}")
        print("REMOTE_CDP_OK")
        context.close()

    mcp = sandbox.commands.run(
        "browser-sandbox-mcp-smoke", user="root", timeout=180
    )
    print(mcp.stdout, end="")
    if mcp.exit_code != 0:
        print(mcp.stderr, end="")
        raise SystemExit(mcp.exit_code)
