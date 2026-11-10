import test from 'node:test';
import assert from 'node:assert/strict';
import { linuxManifest } from '../scripts/update-manifest.mjs';
const signature = Buffer.from('untrusted comment: test\nabc\ntrusted comment: timestamp\tversion:0.2.0\nxyz').toString('base64');
const input = {version:'0.2.0',tag:'linux-v0.2.0',appimage:{name:'Afterglow_0.2.0_amd64.AppImage',signature},deb:{name:'Afterglow_0.2.0_amd64.deb',signature}};
test('Linux update feeds select the installed bundle type, with no unsafe generic fallback', () => {
 const result = linuxManifest(input);
 assert.deepEqual(Object.keys(result.platforms).sort(),['linux-x86_64-appimage','linux-x86_64-deb']);
 assert.match(result.platforms['linux-x86_64-deb'].url,/\.deb$/);
 assert.match(result.platforms['linux-x86_64-appimage'].url,/\.AppImage$/);
 assert.equal(result.platforms['linux-x86_64'],undefined);
});
test('Linux feed refuses wrong-format assets, missing signatures and version substitution', () => {
 for (const modified of [{version:'0.3.0'},{appimage:{...input.appimage,name:'setup.exe'}},{deb:{...input.deb,signature:''}}]) {
  assert.throws(() => linuxManifest({...input,...modified}));
 }
});
