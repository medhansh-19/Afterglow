import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

export function manifest({ version, tag, installer, signature }) {
  if (!/^\d+\.\d+\.\d+$/.test(version)) throw new Error('Use a stable Windows semver version.');
  if (!/^[a-zA-Z0-9._-]+$/.test(tag)) throw new Error('Invalid release tag.');
  if (!/^[a-zA-Z0-9._ -]+\.exe$/.test(installer)) throw new Error('Invalid installer filename.');
  // Tauri signatures are base64-encoded minisign signature files.
  const decoded = Buffer.from(signature.trim(), 'base64').toString('utf8');
  if (!decoded.startsWith('untrusted comment:') || !decoded.includes('trusted comment:')) throw new Error('Invalid updater signature.');
  const trusted = decoded.split('\n').find(line => line.startsWith('trusted comment:')) ?? '';
  if (!trusted.split(/\s+/).includes(`version:${version}`)) throw new Error('Signature version must match the manifest.');
  return { version, notes: `Afterglow ${version} for Windows.`, platforms: {
    'windows-x86_64': { url: `https://github.com/medhansh-19/Afterglow/releases/download/${tag}/${encodeURIComponent(installer)}`, signature: signature.trim() }
  }};
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [directory, version, tag] = process.argv.slice(2);
  const files = readdirSync(directory).filter(f => f.endsWith('.exe') && !f.startsWith('afterglow-lyrics'));
  if (files.length !== 1) throw new Error('Expected exactly one signed installer.');
  const installer = files[0];
  const signature = readFileSync(join(directory, `${installer}.sig`), 'utf8');
  writeFileSync(join(directory, 'windows-latest.json'), JSON.stringify(manifest({ version, tag, installer, signature }), null, 2) + '\n');
}
