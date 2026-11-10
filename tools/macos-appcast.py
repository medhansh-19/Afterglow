#!/usr/bin/env python3
"""Produce and sign a Sparkle appcast with the official Sparkle signing tool."""
import argparse
import base64
import os
import plistlib
import re
import subprocess
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path
from urllib.parse import quote

SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', SPARKLE)


def appcast(info, archive_name, length, signature, tag):
    if not re.fullmatch(r'[A-Za-z0-9._-]+', tag):
        raise ValueError('Invalid immutable release tag')
    if not re.fullmatch(r'[A-Za-z0-9._ -]+\.zip', archive_name):
        raise ValueError('Invalid update archive name')
    if not re.fullmatch(r'\d+(?:\.\d+)*', info['CFBundleVersion']):
        raise ValueError('Invalid build version')
    if info['CFBundleIdentifier'] != 'local.medhansh.afterglow':
        raise ValueError('Unexpected application identity')
    if len(base64.b64decode(signature, validate=True)) != 64 or length <= 0:
        raise ValueError('Missing or malformed EdDSA signature')
    root = ET.Element('rss', version='2.0')
    channel = ET.SubElement(root, 'channel')
    ET.SubElement(channel, 'title').text = 'Afterglow for macOS'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = f"Afterglow {info['CFBundleShortVersionString']}"
    ET.SubElement(item, f'{{{SPARKLE}}}minimumSystemVersion').text = info['LSMinimumSystemVersion']
    ET.SubElement(item, 'enclosure', {
        'url': f'https://github.com/medhansh-19/Afterglow/releases/download/{tag}/{quote(archive_name)}',
        'length': str(length), 'type': 'application/octet-stream',
        f'{{{SPARKLE}}}version': info['CFBundleVersion'],
        f'{{{SPARKLE}}}shortVersionString': info['CFBundleShortVersionString'],
        f'{{{SPARKLE}}}edSignature': signature,
    })
    return ET.tostring(root, encoding='utf-8', xml_declaration=True)


def generate(archive, signer, tag, output):
    private_key = os.environ['MACOS_SPARKLE_PRIVATE_KEY']
    def sign(*arguments):
        return subprocess.check_output([str(signer), '--ed-key-file', '-', *map(str, arguments)], input=private_key, text=True)
    with zipfile.ZipFile(archive) as package:
        info = plistlib.loads(package.read('Afterglow.app/Contents/Info.plist'))
    attributes = ET.fromstring(f'<enclosure xmlns:sparkle="{SPARKLE}" {sign(archive).strip()} />').attrib
    signature = attributes[f'{{{SPARKLE}}}edSignature']
    assert int(attributes['length']) == archive.stat().st_size
    sign('--verify', archive, signature)
    # Verify against the key actually embedded in the candidate, not just the secret's key.
    subprocess.run(['swift', str(Path(__file__).with_name('verify-sparkle-signature.swift')), str(archive), info['SUPublicEDKey'], signature], check=True)
    output.write_bytes(appcast(info, archive.name, archive.stat().st_size, signature, tag))
    sign(output)  # Embeds a signed-feed XML comment; do not modify the XML afterward.
    sign('--verify', output)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('archive', type=Path)
    parser.add_argument('tag')
    parser.add_argument('--signer', type=Path, default=Path('.build/artifacts/sparkle/Sparkle/bin/sign_update'))
    parser.add_argument('--output', type=Path, default=Path('build/appcast.xml'))
    args = parser.parse_args()
    generate(args.archive, args.signer, args.tag, args.output)
