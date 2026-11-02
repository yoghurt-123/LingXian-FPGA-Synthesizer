'use strict';
const fs=require('fs'),crypto=require('crypto'),path=require('path');
const v=JSON.parse(fs.readFileSync('docs/music_hall/protocol_vectors_v1.json','utf8'));
function crc8(bytes){let c=0;for(const b of bytes){c^=b;for(let i=0;i<8;i++)c=(c&0x80)?((c<<1)^0x07)&0xff:(c<<1)&0xff;}return c;}
let fail=0;
function check(c,m){if(!c){console.error('FAIL',m);fail++;}else console.log('OK',m);}
for(const f of v.frames){
 const b=Buffer.from(f.hex,'hex');
 if(f.name.startsWith('BLE ')){
  check(b.length>=5 && b[0]===0xE2, f.name+' E2 header');
  const len=b[3]; check(b.length===len+5, f.name+' length');
  check(crc8(b.subarray(1,4+len))===b[4+len], f.name+' CRC excludes E2');
  check(crc8(b.subarray(0,4+len))!==b[4+len] || f.name!=='BLE CAPS_RSP', f.name+' not old E2-inclusive CRC');
  if(f.name==='BLE BEGIN 40'){check(len===40,'BEGIN payload exactly 40'); check(b[4+len-32]!==undefined,'BEGIN has SHA');}
  if(f.name==='BLE CAPS_RSP'){check(b[4+len]===0x4c,'CAPS_RSP CRC 0x4C for seq 0');}
 } else {
  check(b.length>=6 && b[0]===0xA5 && b[1]===0x5A, f.name+' UART header');
  const len=b[4]; check(b.length===len+6, f.name+' UART length');
  check(crc8(b.subarray(2,5+len))===b[5+len], f.name+' UART CRC');
 }
}
const perf=fs.readFileSync('music_packs/rock_theme_3_full/score/performance.bin');
check(perf.length===v.performance.bytes,'performance bytes');
check(crypto.createHash('sha256').update(perf).digest('hex')===v.performance.sha256,'performance SHA-256 matches vector');
check(v.begin.bytes===40,'frozen BEGIN payload length 40');
check(v.begin.sha_semantics.toLowerCase().includes('performance.bin'),'SHA scope documented');
console.log(fail?'FAIL '+fail:'PASS all shared protocol vectors');
process.exit(fail?1:0);
