import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { signedAsset } from '../../windows/scripts/update-manifest.mjs';

export function linuxManifest({ version, tag, appimage, deb }) {
  return { version, notes: `Afterglow ${version} for Linux.`, platforms: {
    'linux-x86_64-appimage': signedAsset({ version, tag, installer: appimage.name, signature: appimage.signature }, 'AppImage'),
    'linux-x86_64-deb': signedAsset({ version, tag, installer: deb.name, signature: deb.signature }, 'deb')
  }};
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [directory, version, tag] = process.argv.slice(2);
  const files = readdirSync(directory);
  const asset = extension => {
    const names = files.filter(name => name.endsWith(`.${extension}`));
    if (names.length !== 1) throw new Error(`Expected exactly one signed ${extension}.`);
    return { name: names[0], signature: readFileSync(join(directory, `${names[0]}.sig`), 'utf8') };
  };
  writeFileSync(join(directory, 'linux-latest.json'), JSON.stringify(linuxManifest({ version, tag, appimage: asset('AppImage'), deb: asset('deb') }), null, 2) + '\n');
}
