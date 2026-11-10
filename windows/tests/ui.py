"""Shared UI checks in Windows preview mode; does not certify native Windows APIs.
Run a Vite server on port 1420, then python windows/tests/ui.py.
"""
import json
import os
import struct
from pathlib import Path
from playwright.sync_api import sync_playwright, expect

out = Path(os.environ.get("AFTERGLOW_TEST_OUTPUT", "/tmp/afterglow-windows-ui"))
out.mkdir(parents=True, exist_ok=True)
url = os.environ.get("AFTERGLOW_TEST_URL", "http://127.0.0.1:1420/?platform=windows")
chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
store = "afterglow-linux-preview"

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True, executable_path=chrome if os.path.exists(chrome) else None)
    page = browser.new_page(viewport={"width": 1200, "height": 800}, reduced_motion="reduce")
    errors = []
    page.on("pageerror", lambda error: errors.append(str(error)))
    page.goto(url)
    page.wait_for_load_state("networkidle")
    expect(page.locator(".brand")).to_contain_text("WINDOWS PREVIEW")
    expect(page.locator(".preview-note")).to_contain_text("Windows")
    page.set_viewport_size({"width": 640, "height": 480})
    rect = page.locator("#demo").bounding_box()
    assert rect["y"] + rect["height"] <= 480, "Demo action clipped at minimum size"
    page.set_viewport_size({"width": 1200, "height": 800})
    page.get_by_role("button", name="Try the silent demo", exact=True).click()
    expect(page.locator("#title")).to_have_text("Afterglow")
    page.locator("#seek").fill("3")
    page.locator("#seek").dispatch_event("change")
    page.evaluate("document.activeElement.blur()");page.keyboard.press("Space")
    expect(page.locator("#graph svg")).to_be_visible()
    paused = page.locator("#time").inner_text()
    page.wait_for_timeout(1100)
    assert page.locator("#time").inner_text() == paused
    expect(page.locator("#lyric-source")).to_be_hidden()

    page.locator("#controls").click()
    page.get_by_role("button", name="Appearance", exact=True).click()
    expect(page.locator("#preview-graph svg")).to_be_visible()
    expect(page.locator("#preview-status")).to_contain_text("Paused preview")
    page.screenshot(path=str(out / "appearance-preview.png"))
    clock = page.locator('[data-setting="clockSize"]')
    assert clock.get_attribute("min") == "70" and clock.get_attribute("max") == "140"
    for style in ["Minimal", "Flip", "Rounded", "Glass", "Ring", "Analog", "Classic"]:
        page.locator('[data-setting="clockStyle"]').select_option(style)
        expect(page.locator("#clock")).to_have_attribute("data-style", style)
    for marker in ["diamond", "circle", "triangle", "star", "octagon", "rectangle", "sparkle"]:
        page.locator('[data-setting="marker"]').select_option(marker)
        expect(page.locator("#graph")).to_have_attribute("data-marker", marker)
    page.locator('[data-setting="emoji"]').fill("🌙")
    page.locator('[data-setting="albumColor"]').uncheck()
    page.locator('[data-setting="tint"]').fill("#22ccaa")
    page.get_by_role("button", name="Save scene for this song", exact=True).click()
    expect(page.get_by_role("button", name="Update scene for this song", exact=True)).to_be_visible()
    with page.expect_download() as download:
        page.get_by_role("button", name="Export lyric map", exact=True).click()
    download.value.save_as(out / "lyric-map.png")
    assert struct.unpack(">II", (out / "lyric-map.png").read_bytes()[16:24]) == (1600, 1000)

    page.locator("#saved-color-name").fill("Moonlight")
    page.get_by_role("button", name="Save this color", exact=True).click()
    expect(page.locator('[data-color-name="0"]')).to_have_value("Moonlight")
    page.locator('[data-color-name="0"]').fill("Ocean")
    page.locator('[data-color-name="0"]').press("Tab")
    page.locator('[data-preset="lyrics"]').select_option("#6bb0f7")
    expect(page.locator('[data-setting="tint"]')).to_have_value("#6bb0f7")
    page.locator('[data-preset="lyrics"]').select_option("#22ccaa")
    page.get_by_role("button", name="Collections", exact=True).click()
    page.locator("#collection-name").fill("LIKED")
    page.get_by_role("button", name="Create collection", exact=True).click()
    expect(page.locator("#collection-name")).to_have_attribute("aria-invalid", "true")
    assert page.locator(".collection").count() == 2
    page.locator("#collection-name").fill("Late nights")
    page.get_by_role("button", name="Create collection", exact=True).click()
    section = page.locator(".collection").filter(has=page.locator('input[value="Late nights"]'))
    section.get_by_role("button", name="Save current song").click()
    expect(page.locator(".saved-song")).to_have_count(1)
    section.locator('[data-collection-mode]').select_option("album")
    expect(section.locator('[data-collection-mode]')).to_have_value("album")
    section.locator('[data-collection-mode]').select_option("#6bb0f7")
    expect(section.locator('[data-collection-color]')).to_have_value("#6bb0f7")
    section.get_by_role("button", name="Delete collection", exact=True).click()
    deletion = page.get_by_role("dialog", name="Delete Late nights?")
    expect(deletion).to_be_visible()
    expect(page.locator("#cancel-delete")).to_be_focused()
    page.keyboard.press("Escape")
    expect(deletion).to_have_count(0)
    expect(page.locator(".saved-song")).to_have_count(1)
    section.get_by_role("button", name="Delete collection", exact=True).click()
    page.locator("#confirm-delete").click()
    expect(page.locator(".collection")).to_have_count(2)

    page.get_by_role("button", name="Lyric cards", exact=True).click()
    page.locator('[data-card-line="0"]').check()
    page.locator('[data-card-line="1"]').check()
    page.get_by_role("button", name="Save excerpt", exact=True).click()
    expect(page.locator("[data-delete-excerpt]")).to_have_count(1)
    with page.expect_download() as download:
        page.get_by_role("button", name="Export PNG", exact=True).click()
    download.value.save_as(out / "lyric-card.png")
    assert struct.unpack(">II", (out / "lyric-card.png").read_bytes()[16:24]) == (1080, 1350)
    page.get_by_role("button", name="Help", exact=True).click()
    expect(page.get_by_role("heading", name="Afterglow for Windows", exact=True)).to_be_visible()
    assert "MPRIS" not in page.locator("#panel-body").inner_text()
    assert "Wayland" not in page.locator("#panel-body").inner_text()
    page.get_by_role("button", name="Enable global shortcuts", exact=True).click()
    expect(page.locator("#notice")).to_contain_text("installed Windows app")

    # Native API availability errors must not break the UI or silently emulate audio.
    page.get_by_role("button", name="Beat sync", exact=True).click()
    expect(page.locator("#audio-list")).to_contain_text("installed Windows app")
    page.get_by_role("button", name="Lyrics", exact=True).click()
    page.locator("#timing").fill("1.5")
    page.locator("#timing").dispatch_event("input")
    for width, height in [(1440, 900), (1024, 768), (768, 1024), (640, 480)]:
        page.set_viewport_size({"width": width, "height": height})
        assert page.evaluate("document.documentElement.scrollWidth <= innerWidth"), f"Overflow at {width}"
        assert page.locator("#panel").bounding_box()["width"] <= width
        page.locator("#panel-body").evaluate("node => node.scrollTop = node.scrollHeight")
        assert page.locator("#close-panel").is_visible()
    page.set_viewport_size({"width": 1200, "height": 800})
    page.locator("#close-panel").click()
    page.screenshot(path=str(out / "demo.png"))
    page.wait_for_timeout(400)
    saved = page.evaluate(f"JSON.parse(localStorage.getItem('{store}'))")
    assert len(saved["excerpts"]) == 1 and saved["timing"]
    assert saved["colors"] == [{"name": "Ocean", "color": "#22ccaa"}]
    assert all("allowTimedFallback" not in scene for scene in saved["scenes"].values())
    page.reload()
    page.wait_for_load_state("networkidle")
    page.get_by_role("button", name="Try the silent demo", exact=True).click()
    page.locator("#controls").click()
    page.get_by_role("button", name="Lyric cards", exact=True).click()
    expect(page.locator("[data-delete-excerpt]")).to_have_count(1)
    # Invalid saved libraries must be preserved, never overwritten with blank defaults.
    page.evaluate(f"localStorage.setItem('{store}', '{{\"version\":99,\"keep\":\"evidence\"}}')")
    page.reload()
    page.wait_for_load_state("networkidle")
    expect(page.locator("#notice")).to_contain_text("original file has been preserved")
    page.get_by_role("button", name="Try the silent demo", exact=True).click()
    page.locator("#controls").click()
    page.get_by_role("button", name="Appearance", exact=True).click()
    page.locator('[data-setting="tint"]').fill("#abcdef")
    page.wait_for_timeout(400)
    assert json.loads(page.evaluate(f"localStorage.getItem('{store}')"))["keep"] == "evidence"
    assert not errors, errors
    report = {"passed": True, "browser": "Chromium", "platformMode": "Windows preview", "nativeWindowsRuntime": False, "errors": errors, "artifacts": str(out)}
    (out / "report.json").write_text(json.dumps(report, indent=2))
    print("PASS Windows-mode demo, timing, seven clocks/markers, scenes, cards/maps, collection validation/delete/cancel, persistence, invalid-library preservation, native-unavailable errors and narrow layout")
    browser.close()
