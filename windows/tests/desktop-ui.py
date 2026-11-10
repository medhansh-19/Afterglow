"""Wallpaper UI with native events mocked; Explorer integration is tested separately."""
import json, os
from pathlib import Path
from playwright.sync_api import sync_playwright, expect
out=Path(os.environ.get('AFTERGLOW_TEST_OUTPUT','/tmp/afterglow-desktop-ui'));out.mkdir(parents=True,exist_ok=True)
mock=r'''() => {
 let id=0;const callbacks={},listeners={};
 window.__AFTERGLOW_WALLPAPER__=true;
 window.fixture={ready:false,emit(name,payload){for(const cb of listeners[name]||[])callbacks[cb]({event:name,payload});}};
 window.__TAURI_INTERNALS__={transformCallback(fn){callbacks[++id]=fn;return id;},unregisterCallback(id){delete callbacks[id]},async invoke(command,args={}){
  if(command==='plugin:event|listen'){(listeners[args.event] ||= []).push(args.handler);return ++id;}
  if(command==='plugin:event|unlisten')return;
  if(command==='wallpaper_ready'){
   fixture.ready=true;
   fixture.emit('display-state',{settings:{color:'#22ccaa',clock:false,motion:true},track:{title:'Japji Sahib',artist:'Bhai Manpreet Singh Ji Kanpuri',duration:1153},sample:{position:703,duration:1153,rate:1,playing:false},playing:false,lyrics:[]});return;
  }
  if(command==='client_error')throw Error(args.message);
  throw Error('Unexpected command '+command);
 }};
}'''
with sync_playwright() as p:
 browser=p.chromium.launch(headless=True,executable_path='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' if os.path.exists('/Applications/Google Chrome.app') else None)
 page=browser.new_page(viewport={'width':1440,'height':900})
 errors=[];page.on('pageerror',lambda err:errors.append(str(err)))
 page.add_init_script('('+mock+')()');page.goto('http://127.0.0.1:1420/?platform=windows');page.wait_for_load_state('networkidle')
 expect(page.locator('#title')).to_have_text('Japji Sahib');expect(page.locator('#time')).to_have_text('11:43');expect(page.locator('#duration')).to_have_text('19:13')
 assert page.evaluate('fixture.ready')
 assert page.locator('.now-playing button, .now-playing img, .now-playing input').count()==0
 expect(page.get_by_role('progressbar')).to_have_attribute('aria-valuenow','703')
 for width,height in [(1440,900),(1920,1200),(1366,768),(3440,1440),(1080,1920),(3840,2160),(683,384)]:
  page.set_viewport_size({'width':width,'height':height});page.wait_for_timeout(150)
  canvas=page.locator('#waves').bounding_box();footer=page.locator('.now-playing').bounding_box()
  assert canvas['width']==width and canvas['height']==height,(width,height,canvas)
  assert abs(footer['x']+footer['width']/2-width/2)<1
  assert footer['y']+footer['height']<height and footer['y']>=0
  if width in [1440,683]:page.screenshot(path=str(out/f'desktop-{width}.png'))
 page.set_viewport_size({'width':1440,'height':900})
 page.evaluate('''fixture.emit('display-state',{playing:true,audioActive:true,sample:{position:703,duration:1153,rate:1,playing:true},lyrics:[{time:703,end:708,text:'Light comes home',words:[{text:'Light',time:703,end:704},{text:'comes',time:704,end:705},{text:'home',time:705,end:708}]}]})''')
 expect(page.locator('#graph svg')).to_be_visible();before=page.locator('#graph').inner_html()
 page.evaluate("fixture.emit('audio-frame',{level:.8,bands:Array(32).fill(.8)})")
 page.wait_for_timeout(2200)
 assert page.locator('#graph').inner_html()!=before,'Wallpaper words did not advance independently of main-window events'
 assert page.locator('#time').inner_text()!='11:43'
 page.evaluate("fixture.emit('display-state',{playing:false,sample:{position:706,duration:1153,playing:false,rate:1}})")
 expect(page.locator('#time')).to_have_text('11:46');page.wait_for_timeout(1200);expect(page.locator('#time')).to_have_text('11:46')
 # A wallpaper keeps its image after partial preference updates, and can explicitly clear it.
 page.evaluate("fixture.emit('display-state',{settings:{wallpaper:'data:image/svg+xml,<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1\" height=\"1\"><rect width=\"1\" height=\"1\" fill=\"red\"/></svg>',opacity:1}})")
 page.wait_for_timeout(100);page.evaluate("fixture.emit('display-state',{settings:{color:'#ff0000'}})")
 page.wait_for_function("document.querySelector('#waves').getContext('2d').getImageData(0,0,1,1).data[0] > 200")
 page.evaluate("fixture.emit('display-state',{settings:{wallpaper:null}})")
 page.wait_for_function("document.querySelector('#waves').getContext('2d').getImageData(0,0,1,1).data[0] < 100")
 assert not errors,errors
 (out/'desktop-report.json').write_text(json.dumps({'passed':True,'nativeBoundary':'mocked','sizes':['16:10','16:9','ultrawide','portrait','4K','200% short laptop'],'errors':errors},indent=2))
 print('PASS reference footer, exact display bounds, ready handshake, independent lyric timing, pause and direct-audio event handling')
 browser.close()
