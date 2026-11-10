#!/usr/bin/env python3
"""Run an isolated Sparkle fixture using the shipped app and official signer.
Only fixture bundle metadata changes: unique identity, build 34->35 and loopback transport.
"""
import argparse
import base64
import functools
import http.server
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import tempfile
import uuid
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[2]
NS='http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle',NS)

def run(*args,**kwargs): return subprocess.run(list(map(str,args)),check=True,**kwargs)

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('archive',type=Path);p.add_argument('state',type=Path);p.add_argument('--key-file',type=Path,required=True);args=p.parse_args()
 private=args.key_file.read_text()
 work=Path(tempfile.mkdtemp(prefix='afterglow-sparkle-acceptance-'))
 host=work/'host';target=work/'target';web=work/'web'
 for directory in (host,target,web):directory.mkdir()
 mode=work/'mode';mode.write_text('good')
 class Handler(http.server.SimpleHTTPRequestHandler):
  def do_GET(self):
   if 'If-Modified-Since' in self.headers:del self.headers['If-Modified-Since']
   if self.path=='/appcast.xml' and mode.read_text().strip()=='bad-feed':self.path='/bad.xml'
   if self.path=='/Afterglow.zip' and mode.read_text().strip()=='bad-payload':self.path='/bad.zip'
   super().do_GET()
  def end_headers(self):
   self.send_header('Cache-Control','no-store');super().end_headers()
 server=http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Handler,directory=str(web)))
 identifier='local.medhansh.afterglow.acceptance.'+uuid.uuid4().hex[:10]
 key='afterglow.updateAcceptanceSentinel';token=uuid.uuid4().hex
 ent=plistlib.loads((ROOT/'Resources/Afterglow.entitlements').read_bytes())
 ent['com.apple.security.temporary-exception.mach-lookup.global-name']=[identifier+'-spks',identifier+'-spki']
 entitlements=work/'entitlements.plist';entitlements.write_bytes(plistlib.dumps(ent))
 env=dict(os.environ,AFTERGLOW_SIGNING_IDENTITY='-')
 for directory,build in [(host,'34'),(target,'35')]:
  run('ditto','-x','-k',args.archive.resolve(),directory)
  app=directory/'Afterglow.app';info_path=app/'Contents/Info.plist';info=plistlib.loads(info_path.read_bytes())
  info.update({'CFBundleIdentifier':identifier,'CFBundleName':'Afterglow Update Acceptance','CFBundleDisplayName':'Afterglow Update Acceptance','CFBundleVersion':build,'CFBundleShortVersionString':'3.0.7' if build=='34' else '3.0.8','SUFeedURL':f'http://127.0.0.1:{server.server_port}/appcast.xml','SUEnableAutomaticChecks':False})
  info['NSAppTransportSecurity']['NSAllowsLocalNetworking']=True
  info_path.write_bytes(plistlib.dumps(info))
  run('zsh',ROOT/'tools/sign-local.sh',app,entitlements,env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 archive=web/'Afterglow.zip';run('ditto','-c','-k','--norsrc','--keepParent',target/'Afterglow.app',archive)
 signer=ROOT/'.build/artifacts/sparkle/Sparkle/bin/sign_update'
 def sign(*arguments):return subprocess.check_output([str(signer),'--ed-key-file','-',*map(str,arguments)],input=private,text=True).strip()
 signature=sign('-p',archive)
 info=plistlib.loads((target/'Afterglow.app/Contents/Info.plist').read_bytes())
 run('swift',ROOT/'tools/verify-sparkle-signature.swift',archive,info['SUPublicEDKey'],signature)
 root=ET.Element('rss',version='2.0');channel=ET.SubElement(root,'channel');ET.SubElement(channel,'title').text='Afterglow Update Acceptance';item=ET.SubElement(channel,'item');ET.SubElement(item,'title').text='Afterglow Acceptance 3.0.8'
 ET.SubElement(item,'enclosure',{'url':f'http://127.0.0.1:{server.server_port}/Afterglow.zip','length':str(archive.stat().st_size),'type':'application/octet-stream',f'{{{NS}}}version':'35',f'{{{NS}}}shortVersionString':'3.0.8',f'{{{NS}}}edSignature':signature})
 feed=web/'appcast.xml';feed.write_bytes(ET.tostring(root,encoding='utf-8',xml_declaration=True));sign(feed);sign('--verify',feed)
 (web/'bad.xml').write_bytes(feed.read_bytes().replace(b'Afterglow Acceptance 3.0.8',b'Afterglow Altered 3.0.8'))
 corrupted=bytearray(archive.read_bytes());corrupted[0]^=1;(web/'bad.zip').write_bytes(corrupted)
 state={'work':str(work),'app':str(host/'Afterglow.app'),'identifier':identifier,'mode':str(mode),'sentinelKey':key,'sentinel':token,'server':f'http://127.0.0.1:{server.server_port}','pid':os.getpid()}
 args.state.write_text(json.dumps(state,indent=2));print(json.dumps(state),flush=True)
 signal.signal(signal.SIGTERM,lambda *_: (_ for _ in ()).throw(SystemExit(0)))
 try:server.serve_forever()
 finally:server.server_close()
