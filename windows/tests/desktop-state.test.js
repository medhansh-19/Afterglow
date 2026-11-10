import test from 'node:test';
import assert from 'node:assert/strict';
import { createDesktopState } from '../../linux/src/desktop-state.js';
import { matchingAudioStream, audioStatus } from '../../linux/src/audio-source.js';
const player={identity:'Spotify',bus:'SpotifyAB.SpotifyMusic'};
test('player audio is chosen only for one matching executable, never a whole browser or unrelated stream',()=>{
  const spotify={index:101,binary:'Spotify.exe'}, other={index:202,binary:'chrome.exe'};
  assert.equal(matchingAudioStream([spotify,other],player),spotify);
  assert.equal(matchingAudioStream([spotify,{index:303,binary:'Spotify.exe'}],player),null);
  assert.equal(matchingAudioStream([other],{bus:'chrome.exe',identity:'Browser'}),null);
  assert.equal(matchingAudioStream([other],player),null);
  assert.equal(matchingAudioStream([{index:9,binary:'AppleMusic.exe'}],{identity:'Apple Music'}).index,9);
  assert.equal(matchingAudioStream([other],player,'chrome.exe'),other); // Explicit previous selection only.
});
test('audio status distinguishes capture setup, silence, stale frames and actual signal',()=>{
  const state={enabled:true,pending:false,active:true,playing:true,sleeping:false,visible:true,now:5000,started:1000,lastFrame:4900,lastSignal:4800};
  assert.match(audioStatus(state),/Listening/);
  assert.match(audioStatus({...state,lastSignal:0}),/silent/);
  assert.match(audioStatus({...state,lastFrame:1000}),/No audio received/);
  assert.match(audioStatus({...state,now:1500,lastFrame:0}),/Waiting/);
  assert.match(audioStatus({...state,pending:true}),/Connecting/);
  for(const change of [{playing:false},{sleeping:true},{visible:false}]) assert.match(audioStatus({...state,...change}),/paused/);
  assert.equal(audioStatus({...state,enabled:false}),'Beat sync off');
});
test('wallpaper owns word timing and playback interpolation while the main window is throttled',()=>{
  const desktop=createDesktopState();
  desktop.receive({playing:true,sample:{position:0,duration:100,rate:1,playing:true},track:{title:'Song',duration:100},lyrics:[{time:0,text:'Light returns',words:[{text:'Light',time:0,end:1},{text:'returns',time:1,end:2}]}]},1000);
  const first=desktop.frame(1000),next=desktop.frame(2500);
  assert.equal(first.position,0);assert.equal(next.position,1.5);
  assert.notEqual(first.line.active,next.line.active);
  desktop.receive({playing:false,sample:{position:1.5,duration:100,rate:1,playing:false}},3000);
  assert.equal(desktop.frame(5000).position,1.5);
});
test('display deltas retain the wallpaper and lyrics; direct audio expires and stops on pause or sleep',()=>{
  const d=createDesktopState();
  d.receive({settings:{wallpaper:'data:image',color:'#22ccaa'},lyrics:[{time:0,text:'Light'}],playing:true,sample:{position:3,playing:true,rate:1,duration:100},audioActive:true},1000);
  d.receive({settings:{color:'#ff0000'}},1100);
  assert.equal(d.frame(1100).settings.wallpaper,'data:image');assert.equal(d.frame(1100).lyrics.length,1);
  d.audio({level:.7,bands:Array(32).fill(.5)},1100);
  assert.equal(d.frame(1200).audio.level,.7);assert.equal(d.frame(1500).audio.level,0);
  d.power({sleeping:true});assert.equal(d.frame(1200).playing,false);assert.equal(d.frame(1200).audio.level,0);
  d.power({sleeping:false});d.receive({playing:false},1600);d.audio({level:1,bands:Array(32).fill(1)},1600);assert.equal(d.frame(1600).audio.level,0);
  d.receive({settings:{wallpaper:null},lyrics:[]},1700);assert.equal(d.frame(1700).settings.wallpaper,null);assert.equal(d.frame(1700).lyrics.length,0);
});
