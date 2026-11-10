#!/usr/bin/env python3
"""Native acceptance against signed CI artifacts. Test transport binds loopback only."""
import argparse
import functools
import hashlib
import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[2]

def run(*args, **kwargs):
    return subprocess.run(list(map(str, args)), check=True, **kwargs)

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def one(directory, pattern):
    files = list(directory.rglob(pattern))
    assert len(files) == 1, (pattern, files)
    return files[0]

def patch_runner(source, destination, kind):
    data = source.read_bytes()
    old = b'__TAURI_BUNDLE_TYPE_VAR_UNK'
    assert old in data, 'Missing native bundler marker'
    destination.write_bytes(data.replace(old, b'__TAURI_BUNDLE_TYPE_VAR_' + kind.encode()))
    destination.chmod(0o755)
    return destination

def windows_smoke(executable, output):
    run('pwsh', '-NoProfile', '-File', ROOT/'windows/tests/native-smoke.ps1', '-AppPath', executable, '-OutputDirectory', output)

def windows_version(path):
    env = dict(os.environ, AFTERGLOW_ACCEPTANCE_EXE=str(path))
    return subprocess.check_output(['pwsh','-NoProfile','-Command','(Get-Item $env:AFTERGLOW_ACCEPTANCE_EXE).VersionInfo.FileVersion'],env=env,text=True).strip()

def accept(platform, packages, runner, baseline, output):
    output.mkdir(parents=True, exist_ok=True)
    config = ROOT / ('windows/tauri.windows.conf.json' if platform == 'windows' else 'linux/src-tauri/tauri.conf.json')
    version = json.loads(config.read_text())['version']
    with tempfile.TemporaryDirectory(prefix='afterglow-update-acceptance-') as temporary:
        work = Path(temporary)
        server_root = work/'server'; server_root.mkdir()
        payloads = {}
        patterns = [('windows-x86_64','*setup.exe')] if platform == 'windows' else [('linux-x86_64-deb','*.deb'),('linux-x86_64-appimage','*.AppImage')]
        for target, pattern in patterns:
            package = one(packages, pattern)
            shutil.copy2(package, server_root/package.name)
            payloads[target] = {'url':package.name,'signature':Path(str(package)+'.sig').read_text().strip()}
        handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(server_root))
        server = http.server.ThreadingHTTPServer(('127.0.0.1',0), handler)
        threading.Thread(target=server.serve_forever,daemon=True).start()
        base = f'http://127.0.0.1:{server.server_port}'
        good = {'version':version, 'platforms':{key:{**value,'url':base+'/'+value['url']} for key,value in payloads.items()}}
        (server_root/'good.json').write_text(json.dumps(good))
        bad = json.loads(json.dumps(good))
        for value in bad['platforms'].values(): value['signature'] = 'invalid-signature'
        (server_root/'bad.json').write_text(json.dumps(bad))
        reports = []
        def invoke(binary, destination, mode, current='0.1.1', feed='good.json', root=False):
            report = output/f'{len(reports):02d}-{mode}.json'
            args = [str(binary), str(config), current, base+'/'+feed, str(destination), mode, str(report)]
            if root: args = ['sudo', *args]
            run(*args, timeout=240)
            assert report.exists(), 'Acceptance runner did not produce a result'
            reports.append(str(report.name))
        try:
            if platform == 'windows':
                executable = work/'installed/afterglow-windows.exe'
                old = one(baseline, '*setup.exe')
                assert digest(old) == 'f9a877d71ba2f2ced8ac83a668ebc4650e964bba6706b0a1676799967766e6c7', 'Published baseline differs from accepted 0.1.1'
                install = subprocess.run([str(old),'/S',f'/D={executable.parent}'],check=True)
                windows_smoke(executable,output/'before')
                line = next(line for line in (output/'before/native.log').read_text().splitlines() if line.startswith('library-path:'))
                library = Path(line.split(':',1)[1])
                value = json.loads(library.read_text(encoding='utf-8-sig'))
                value['colors'] = [{'name':'Updater acceptance','color':'#22ccaa'}]
                library.write_text(json.dumps(value),encoding='utf-8')
                saved = digest(library)
                binary = patch_runner(runner,work/'nsis-acceptance.exe','NSS')
                before = digest(executable)
                for mode, current, feed in [('none',version,'good.json'),('none','99.0.0','good.json'),('reject','0.1.1','bad.json'),('reject','0.1.1','missing.json'),('verify','0.1.1','good.json')]:
                    invoke(binary,executable,mode,current,feed)
                    assert digest(executable)==before and digest(library)==saved, 'Check/download changed installation or data'
                invoke(binary,executable,'install')
                deadline = time.monotonic()+180
                while time.monotonic()<deadline:
                    try:
                        if windows_version(executable).startswith(version): break
                    except (OSError,subprocess.SubprocessError): pass
                    time.sleep(1)
                else: raise AssertionError('Native NSIS updater did not install the new version')
                assert digest(library)==saved, 'Upgrade modified the saved library'
                windows_smoke(executable,output/'after')
                assert json.loads(library.read_text(encoding='utf-8-sig'))['colors'][0]['name']=='Updater acceptance'
            else:
                old_deb = one(baseline,'*.deb')
                new_deb = one(packages,'*.deb')
                run('sudo','apt-get','install','-y',old_deb)
                package_name = subprocess.check_output(['dpkg-deb','-f',str(new_deb),'Package'],text=True).strip()
                executable = Path('/usr/bin/afterglow-linux')
                assert executable.exists(), 'Installed Linux executable missing'
                data = work/'data/local.medhansh.afterglow.linux'; data.mkdir(parents=True)
                library = data/'library.json'
                library.write_text(json.dumps({'settings':{'clockSize':120},'colors':[{'name':'Updater acceptance','color':'#22ccaa'}]}))
                saved = digest(library)
                deb_runner = patch_runner(runner,work/'deb-acceptance','DEB')
                before = digest(executable)
                for mode,current,feed in [('none',version,'good.json'),('none','99.0.0','good.json'),('reject','0.1.0','bad.json'),('reject','0.1.0','missing.json'),('verify','0.1.0','good.json')]:
                    invoke(deb_runner,executable,mode,current,feed)
                    assert digest(executable)==before and digest(library)==saved
                invoke(deb_runner,executable,'install',current='0.1.0',root=True)
                actual = subprocess.check_output(['dpkg-query','-W','-f=${Version}',package_name],text=True).strip()
                assert actual==version, (actual,version)
                assert digest(library)==saved
                env=dict(os.environ,XDG_DATA_HOME=str(work/'data'))
                run('xvfb-run','-a','-s','-screen 0 1440x900x24','dbus-run-session','--','bash',ROOT/'linux/tests/native-smoke.sh',executable,env=env)
                assert json.loads(library.read_text())['colors'][0]['name']=='Updater acceptance'
                appimage = one(packages,'*.AppImage')
                old_image = one(baseline,'*.AppImage')
                destination=work/'Afterglow.AppImage'; shutil.copy2(old_image,destination); destination.chmod(0o755)
                image_runner=patch_runner(runner,work/'appimage-acceptance','APP')
                invoke(image_runner,destination,'install',current='0.1.0')
                assert digest(destination)==digest(appimage), 'AppImage replacement does not match signed release'
                assert os.access(destination,os.X_OK) and digest(library)==saved
                readonly=work/'readonly';readonly.mkdir();target=readonly/'Afterglow.AppImage';shutil.copy2(old_image,target)
                previous=digest(target);readonly.chmod(0o555)
                try:
                    invoke(image_runner,target,'install-fail',current='0.1.0')
                    assert digest(target)==previous, 'Read-only failure modified original AppImage'
                finally: readonly.chmod(0o755)
            (output/'acceptance.json').write_text(json.dumps({'passed':True,'platform':platform,'version':version,'signedDownload':True,'tamperRejected':True,'equalAndOlderRejected':True,'networkFailureRejected':True,'nativeUpgrade':True,'libraryPreserved':True,'reports':reports},indent=2))
        finally: server.shutdown()

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('platform',choices=['windows','linux'])
    parser.add_argument('packages',type=Path)
    parser.add_argument('runner',type=Path)
    parser.add_argument('baseline',type=Path)
    parser.add_argument('output',type=Path)
    args=parser.parse_args()
    accept(args.platform,args.packages.resolve(),args.runner.resolve(),args.baseline.resolve(),args.output.resolve())
