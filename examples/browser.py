# Copyright (c) 2024 Tencent Inc.
# SPDX-License-Identifier: Apache-2.0

from __future__ import annotations

import json
import os
from pathlib import Path
from urllib.request import urlopen

from dotenv import load_dotenv
from e2b import Sandbox
from playwright.sync_api import sync_playwright


load_dotenv(dotenv_path=Path(__file__).parents[1] / ".env", override=False)

template_id = os.environ["CUBE_TEMPLATE_ID"]

with Sandbox.create(template=template_id, timeout=300) as sandbox:
    print(sandbox.get_info())
    cdp_base = f"https://{sandbox.get_host(9000)}/cdp"
    with urlopen(f"{cdp_base}/json/version") as response:
        cdp_url = json.load(response)["webSocketDebuggerUrl"].replace(
            "ws://", "wss://", 1
        )

    with sync_playwright() as playwright:
        browser = playwright.chromium.connect_over_cdp(cdp_url)
        context = browser.new_context(ignore_https_errors=True)
        page = context.new_page()
        page.goto("https://example.com", wait_until="domcontentloaded")
        print(page.title())
        context.close()
        browser.close()
