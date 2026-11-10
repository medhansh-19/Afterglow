#!/usr/bin/env python3
"""Check the real packaged app, framework, XPC helpers, entitlements and loader paths."""
import argparse
import base64
import plistlib
import subprocess
import tempfile
import time
from pathlib import Path


def verify(archive, launch=False, universal=True):
    with tempfile.TemporaryDirectory(prefix='afterglow-macos-check-') as directory:
        subprocess.run(['ditto', '-x', '-k', str(archive), directory], check=True)
        app = Path(directory) / 'Afterglow.app'
        info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        assert info['CFBundleIdentifier'] == 'local.medhansh.afterglow'
        assert len(base64.b64decode(info['SUPublicEDKey'], validate=True)) == 32
        assert info['SUFeedURL'].startswith('https://github.com/medhansh-19/Afterglow/releases/download/macos-updates/')
        assert info['SUVerifyUpdateBeforeExtraction'] is True
        assert info['SURequireSignedFeed'] is True
        assert info['SUSignedFeedFailureExpirationInterval'] == 0
        assert info['SUEnableInstallerLauncherService'] is True
        assert info['SUScheduledCheckInterval'] == 21600
        executable = app / 'Contents/MacOS/Afterglow'
        framework = app / 'Contents/Frameworks/Sparkle.framework'
        assert (framework / 'Versions/B/XPCServices/Installer.xpc').is_dir()
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
        architectures = subprocess.check_output(['lipo', '-archs', str(executable)], text=True).split()
        if universal:
            assert {'arm64', 'x86_64'} <= set(architectures), architectures
        dependencies = subprocess.check_output(['otool', '-L', str(executable)], text=True)
        assert '@rpath/Sparkle.framework/' in dependencies
        load_commands = subprocess.check_output(['otool', '-l', str(executable)], text=True)
        assert '@executable_path/../Frameworks' in load_commands
        entitlements = plistlib.loads(subprocess.check_output(['codesign', '-d', '--entitlements', ':-', str(app)], stderr=subprocess.DEVNULL))
        assert entitlements['com.apple.security.temporary-exception.mach-lookup.global-name'] == [f"{info['CFBundleIdentifier']}-spks", f"{info['CFBundleIdentifier']}-spki"]
        if launch:
            log = Path(directory) / 'launch.log'
            with log.open('w') as stream:
                process = subprocess.Popen([str(executable), '--demo'], stdout=stream, stderr=stream)
                try:
                    time.sleep(6)
                    assert process.poll() is None, log.read_text()
                finally:
                    if process.poll() is None:
                        process.terminate()
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait()
            assert 'Library not loaded' not in log.read_text()
        print('Packaged macOS updater, nested signatures, architectures and launch verified.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('archive', type=Path)
    parser.add_argument('--launch', action='store_true')
    parser.add_argument('--native-only', action='store_true')
    args = parser.parse_args()
    verify(args.archive, args.launch, not args.native_only)
