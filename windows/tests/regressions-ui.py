"""Windows UI regressions with a mocked native command boundary; no hardware claims."""
import json, os
from pathlib import Path
from playwright.sync_api import sync_playwright, expect
root = Path(__file__).resolve().parents[2]
out = Path(os.environ.get('AFTERGLOW_TEST_OUTPUT', '/tmp/afterglow-windows-fixes-ui'))
out.mkdir(parents=True, exist_ok=True)
demo = json.loads((root/'linux/src/demo.json').read_text())
mock = r'''(lyrics) => {
  let id = 0; const callbacks = {}, listeners = {};
  window.fixture = { calls: [], playing: true, title: "Test track", fail: false,
    emit(name, payload) { for (const cb of listeners[name] || []) callbacks[cb]({ event: name, payload }); } };
  window.__TAURI_INTERNALS__ = {
    transformCallback(callback) { callbacks[++id] = callback; return id; },
    unregisterCallback(callback) { delete callbacks[callback]; },
    async invoke(command, args = {}) {
      fixture.calls.push({ command, args });
      switch (command) {
        case "plugin:event|listen": (listeners[args.event] ||= []).push(args.handler); return ++id;
        case "plugin:event|unlisten": return;
        case "load_library": return {};
        case "save_library": return;
        case "players": return [{bus:"spotify", identity:"Spotify", title:fixture.title, artist:"Test artist", album:"Test album", duration:120, position:3, rate:1, playing:fixture.playing, canSeek:true}];
        case "transport": if (args.action === "toggle") fixture.playing = !fixture.playing; return;
        case "lyrics": return lyrics;
        case "artwork": return null;
        case "ui_ready": return null;
        case "audio_streams": return [{index:101,name:"Spotify",binary:"Spotify.exe"},{index:202,name:"Other player",binary:"other.exe"}];
        case "audio_start": if (fixture.fail) throw Error("Audio unavailable. Refresh streams to reconnect."); return;
        case "audio_stop": return;
        case "client_error": return;
      }
      throw Error("Unexpected command: " + command);
    }
  };
}'''
with sync_playwright() as p:
    browser = p.chromium.launch(headless=True, executable_path='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' if os.path.exists('/Applications/Google Chrome.app') else None)
    page = browser.new_page(viewport={'width':1200,'height':800}, reduced_motion='reduce')
    errors=[]; page.on('pageerror', lambda e: errors.append(str(e)))
    page.add_init_script('(' + mock + ')(' + json.dumps(demo) + ')')
    page.goto('http://127.0.0.1:1420/?platform=windows'); page.wait_for_load_state('networkidle')
    expect(page.locator('#title')).to_have_text('Test track')
    page.locator('#controls').click(); page.locator('[data-tab="audio"]').click()
    page.locator('[data-audio="101"]').click()
    expect(page.locator('#beat-state')).to_contain_text('Beat sync ·')
    assert page.locator('#panel').evaluate('el=>el.open'), 'Stream selection should allow in-place verification'
    count = lambda cmd: page.evaluate('(cmd) => fixture.calls.filter(c=>c.command===cmd).length', cmd)
    starts, stops = count('audio_start'), count('audio_stop')
    page.locator('[data-tab="appearance"]').click()
    assert count('audio_start') == starts and count('audio_stop') == stops, 'Controls stopped live beat capture'
    expect(page.locator('#appearance-beat-state')).to_have_text('Listening')
    page.screenshot(path=str(out/'appearance-1200.png'))
    page.locator('[data-setting="albumColor"]').uncheck(); page.locator('[data-setting="tint"]').fill('#22ccaa')
    page.wait_for_timeout(250)
    first = page.locator('#panel').evaluate('el=>el.style.getPropertyValue("--glass-2")')
    assert first
    page.locator('[data-setting="tint"]').fill('#ff0000'); page.wait_for_timeout(250)
    assert page.locator('#panel').evaluate('el=>el.style.getPropertyValue("--glass-2")') != first
    for width,height in [(640,480),(1920,1080),(3440,1440),(1080,1920),(3840,2160)]:
        page.set_viewport_size({'width':width,'height':height}); page.wait_for_timeout(150)
        canvas=page.locator('#waves').bounding_box(); assert canvas['width']==width and canvas['height']==height
        box=page.locator('#panel').bounding_box(); assert box['width']<=800 and box['height']<=700
        assert box['y']>=0 and box['y']+box['height']<=height
        page.locator('#panel-body').evaluate('el=>el.scrollTop=el.scrollHeight')
        done=page.locator('#done-panel').bounding_box(); assert done['y']+done['height']<=height
        if width in [640,3440]: page.screenshot(path=str(out/f'appearance-{width}.png'))
    page.set_viewport_size({'width':1200,'height':800})
    page.locator('#done-panel').click()
    assert count('audio_stop')==stops
    page.get_by_role('button',name='Pause',exact=True).click()
    expect(page.locator('#play')).to_have_attribute('aria-label','Play'); assert count('audio_stop') > stops
    page.get_by_role('button',name='Play',exact=True).click()
    expect(page.locator('#beat-state')).to_contain_text('Beat sync ·'); assert count('audio_start') > starts
    page.evaluate('fixture.title="Next track"'); page.wait_for_timeout(1400)
    expect(page.locator('#title')).to_have_text('Next track')
    assert page.evaluate('fixture.calls.filter(c=>c.command==="audio_start").at(-1).args.index')==101
    page.locator('#controls').click();page.locator('[data-tab="audio"]').click();page.locator('[data-audio="202"]').click()
    expect(page.locator('#beat-state')).to_contain_text('Beat sync ·')
    calls=page.evaluate('fixture.calls.filter(c=>["audio_start","audio_stop"].includes(c.command)).slice(-2)')
    assert calls[0]['command']=='audio_stop' and calls[1]['args']['index']==202, calls
    page.evaluate('fixture.fail=true');page.locator('[data-audio="101"]').click()
    expect(page.locator('#notice')).to_contain_text('Audio unavailable')
    page.locator('#dismiss-notice').click(); expect(page.locator('#notice')).to_be_hidden()
    page.evaluate('fixture.fail=false');page.locator('[data-audio="101"]').click()
    expect(page.locator('#beat-state')).to_contain_text('Beat sync ·')
    page.evaluate('fixture.emit("audio-ended", "Stream ended. Refresh streams.")')
    expect(page.locator('#notice')).to_be_visible()
    page.wait_for_timeout(8300);expect(page.locator('#notice')).to_be_hidden()
    assert not errors, errors
    (out/'report.json').write_text(json.dumps({'passed':True,'nativeBoundary':'mocked','errors':errors,'viewports':['640x480','1920x1080','3440x1440','1080x1920','3840x2160']},indent=2))
    print('PASS capture in Controls, pause/resume, song changes, stream switching, error/retry/dismiss/expiry, live glass color and adaptive panel/canvas')
    browser.close()
