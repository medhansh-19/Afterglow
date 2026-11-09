"""Functional browser checks. Run against npm run dev; native platform checks are separate."""
import json, os
from pathlib import Path
from playwright.sync_api import sync_playwright, expect
out=Path(os.environ.get('AFTERGLOW_TEST_OUTPUT','/tmp/afterglow-linux-ui'));out.mkdir(parents=True,exist_ok=True)
with sync_playwright() as p:
    browser=p.chromium.launch(headless=True,executable_path=os.environ.get('AFTERGLOW_CHROMIUM_BINARY') or ('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' if os.path.exists('/Applications/Google Chrome.app') else None))
    page=browser.new_page(viewport={'width':1200,'height':800},reduced_motion='reduce')
    errors=[];page.on('pageerror',lambda err:errors.append(str(err)))
    page.goto('http://127.0.0.1:1420');page.wait_for_load_state('networkidle')
    expect(page.get_by_role('heading',name='Put on a song. Stay a little longer.')).to_be_visible()
    page.set_viewport_size({'width':640,'height':480});page.wait_for_timeout(100)
    rect=page.locator('#demo').bounding_box();assert rect['y']+rect['height']<=480,'Demo action clipped at minimum window size'
    page.set_viewport_size({'width':1200,'height':800})
    page.get_by_role('button',name='Try the silent demo',exact=True).click()
    expect(page.locator('#title')).to_have_text('Afterglow')
    expect(page.locator('#lyric-source')).to_contain_text('Word timed')
    page.locator('#seek').fill('3');page.locator('#seek').dispatch_event('change')
    expect(page.locator('#graph svg')).to_be_visible()
    page.get_by_role('button',name='Pause',exact=True).click()
    paused=page.locator('#time').inner_text();page.wait_for_timeout(1100);assert page.locator('#time').inner_text()==paused
    page.locator('#controls').click();page.get_by_role('button',name='Appearance',exact=True).click()
    page.locator('[data-setting="clockStyle"]').select_option('Analog')
    page.locator('[data-setting="marker"]').select_option('circle')
    page.locator('[data-setting="albumColor"]').uncheck()
    page.locator('[data-setting="tint"]').fill('#22ccaa')
    page.get_by_role('button',name='Save scene for this song',exact=True).click()
    expect(page.get_by_role('button',name='Update scene for this song',exact=True)).to_be_visible()
    with page.expect_download() as map_download:page.get_by_role('button',name='Export lyric map',exact=True).click()
    map_download.value.save_as(out/'lyric-map.png');assert (out/'lyric-map.png').read_bytes().startswith(b'\x89PNG')
    page.get_by_role('button',name='Collections',exact=True).click()
    page.locator('#collection-name').fill('Late nights');page.get_by_role('button',name='Create collection').click()
    section=page.locator('.collection').filter(has=page.locator('input[value="Late nights"]'))
    section.get_by_role('button',name='Save current song').click()
    expect(page.locator('.saved-song')).to_have_count(1)
    page.get_by_role('button',name='Lyric cards',exact=True).click()
    page.locator('[data-card-line="0"]').check();page.locator('[data-card-line="1"]').check()
    page.get_by_role('button',name='Save excerpt',exact=True).click()
    expect(page.locator('[data-delete-excerpt]')).to_have_count(1)
    with page.expect_download() as downloaded:page.get_by_role('button',name='Export PNG',exact=True).click()
    download=downloaded.value;download.save_as(out/'lyric-card.png');assert (out/'lyric-card.png').read_bytes().startswith(b'\x89PNG')
    page.get_by_role('button',name='Lyrics',exact=True).click();page.locator('#timing').fill('1.5');page.locator('#timing').dispatch_event('input')
    page.get_by_role('button',name='Player',exact=True).click();page.get_by_role('button',name='Disconnect',exact=True).click()
    page.wait_for_timeout(3200);expect(page.locator('#welcome')).to_be_visible()
    page.locator('#close-panel').click();page.wait_for_timeout(300)
    saved=page.evaluate("JSON.parse(localStorage.getItem('afterglow-linux-preview'))")
    assert saved['collections'][2]['name']=='Late nights' and len(saved['excerpts'])==1
    page.reload();page.wait_for_load_state('networkidle');page.get_by_role('button',name='Try the silent demo',exact=True).click()
    page.locator('#seek').fill('3');page.locator('#seek').dispatch_event('change');page.get_by_role('button',name='Pause',exact=True).click();expect(page.locator('#graph svg')).to_be_visible();page.wait_for_timeout(400);page.screenshot(path=str(out/'demo-1200.png'))
    page.locator('#controls').click();page.get_by_role('button',name='Collections',exact=True).click();expect(page.locator('.saved-song')).to_have_count(1)
    for width,height in [(1440,900),(1024,768),(768,1024),(640,700)]:
        page.set_viewport_size({'width':width,'height':height});page.wait_for_timeout(100)
        assert page.evaluate('document.documentElement.scrollWidth<=innerWidth'),f'Overflow at {width}'
        assert page.locator('#panel').bounding_box()['width']<=width
    # The wallpaper must show untimed fallback/imported lyrics as literal text,
    # then clear them when a timed recording replaces them. It owns no player.
    wallpaper=browser.new_page(viewport={'width':1200,'height':800})
    wallpaper.on('pageerror',lambda err:errors.append(str(err)))
    wallpaper.add_init_script("""
      window.__AFTERGLOW_WALLPAPER__ = true;
      window.__TAURI_INTERNALS__ = {
        transformCallback(callback) { window.deliverDisplay = callback; return 1; },
        async invoke(command, args) {
          if (command === 'plugin:event|listen' && args.event === 'display-state') return 1;
          throw Error('Unexpected wallpaper command: ' + command);
        }
      };
      window.sendDisplay = plainText => window.deliverDisplay({payload:{
        plainText, settings:{}, playing:false, audio:{level:0,bands:[]},
        line:{words:[],active:-1,index:-1}
      }});
    """)
    wallpaper.goto('http://127.0.0.1:1420');wallpaper.wait_for_load_state('networkidle')
    wallpaper.evaluate("window.sendDisplay('सितारे ✨ <script>literal</script>')")
    expect(wallpaper.locator('#plain-text')).to_have_text('सितारे ✨ <script>literal</script>')
    expect(wallpaper.locator('#plain-text')).to_be_visible()
    wallpaper.evaluate("window.sendDisplay('')")
    expect(wallpaper.locator('#plain-text')).to_be_hidden()
    wallpaper.close()
    assert not errors,errors
    (out/'report.json').write_text(json.dumps({'passed':True,'errors':errors,'screenshots':str(out)},indent=2))
    print('PASS browser demo, seek/pause, scene, collection, excerpt/export, persistence, disconnect, responsive controls and untimed wallpaper lyrics')
    browser.close()
