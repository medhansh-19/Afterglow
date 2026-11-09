import test from 'node:test';
import assert from 'node:assert/strict';
import { manifest } from '../scripts/update-manifest.mjs';
const valid = { version: '0.2.1', tag: 'windows-v0.2.1', installer: 'Afterglow_0.2.1_x64-setup.exe', signature: Buffer.from('untrusted comment: signature\nabc\ntrusted comment: timestamp\nxyz').toString('base64') };
test('feed selects Windows only and immutable release asset', () => {
 const result = manifest(valid);
 assert.deepEqual(Object.keys(result.platforms), ['windows-x86_64']);
 assert.match(result.platforms['windows-x86_64'].url, /windows-v0.2.1\/Afterglow/);
 assert.equal(result.version, '0.2.1');
});
test('reject malformed versions, URLs, missing signatures', () => {
 for (const input of [{version:'0.2'}, {tag:'../latest'}, {installer:'https://evil/setup.exe'}, {signature:''}]) {
   assert.throws(() => manifest({...valid, ...input}));
 }
});
