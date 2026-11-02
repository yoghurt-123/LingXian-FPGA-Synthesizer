'use strict';
// Full MIDI analysis for music-hall package authoring. Read-only.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
function rv(b,p){let v=0,n=0;while(p<b.length){const x=b[p++];v=(v<<7)|(x&127);n++;if(!(x&128))break;if(n>4)throw Error('bad varlen');}return{v,p,n};}
function u32(b,o){return b.readUInt32BE(o)} function u16(b,o){return b.readUInt16BE(o)} function s(b,o,n){return b.subarray(o,o+n).toString('utf8')}
function analyze(file){
 const b=fs.readFileSync(file);if(s(b,0,4)!=='MThd')throw Error('not midi');
 const hlen=u32(b,4),format=u16(b,8),ntracks=u16(b,10),division=u16(b,12),pos0=8+hlen;
 let pos=pos0;const tracks=[],tempos=[],timesigs=[];
 for(let ti=0;ti<ntracks&&pos+8<=b.length;ti++){
  if(s(b,pos,4)!=='MTrk')throw Error('MTrk at '+pos);const len=u32(b,pos+4),start=pos+8,end=start+len;let p=start,tick=0,running=0;
  const notesOn=new Map(),notes=[],progs=[],cc=new Map(),controls={pitchBend:0,channelPressure:0,polyPressure:0,sysex:0},channels=new Set();let name='';
  while(p<end){const d=rv(b,p);tick+=d.v;p=d.p;if(p>=end)break;let st=b[p];if(st<0x80){if(!running)throw Error('running at '+p);st=running}else{p++;if(st<0xf0)running=st}
   if(st===0xff){const type=b[p++];const l=rv(b,p);p=l.p;const data=b.subarray(p,p+l.v);p+=l.v;if(type===0x03)name=data.toString('utf8').replace(/\0/g,'');if(type===0x51&&l.v===3)tempos.push({tick,usPerQuarter:(data[0]<<16)|(data[1]<<8)|data[2]});if(type===0x58&&l.v>=2)timesigs.push({tick,numerator:data[0],denominator:1<<data[1]});if(type===0x2f)break;continue}
   if(st===0xf0||st===0xf7){const l=rv(b,p);p=l.p+l.v;controls.sysex++;continue}
   const cmd=st&0xf0,ch=st&15;channels.add(ch);if(cmd===0xc0){const d=b[p++];progs.push({tick,ch,program:d});continue}
   if(cmd===0xd0){b[p++];controls.channelPressure++;continue}
   const d1=b[p++];let d2;if(cmd!==0xd0)d2=b[p++];
   if(cmd===0xa0){controls.polyPressure++;continue}
   if(cmd===0xb0){cc.set(d1,(cc.get(d1)||0)+1);continue}
   if(cmd===0xe0){controls.pitchBend++;continue}
   if(cmd===0x90&&d2>0){notesOn.set(ch+':'+d1,{tick,key:d1,ch,vel:d2});continue}
   if(cmd===0x80||(cmd===0x90&&d2===0)){const n=notesOn.get(ch+':'+d1);if(n){notesOn.delete(ch+':'+d1);notes.push({tick:n.tick,key:n.key,ch:n.ch,vel:n.vel,dur:tick-n.tick,end:tick})}continue}
  }
  for(const n of notesOn.values())notes.push({tick:n.tick,key:n.key,ch:n.ch,vel:n.vel,dur:tick-n.tick,end:tick});
  notes.sort((a,b)=>a.tick-b.tick||a.key-b.key);tracks.push({index:ti,name,channels:[...channels].sort(),programs:progs,notes,cc:Object.fromEntries([...cc.entries()].sort((a,b)=>a[0]-b[0])),controls,endTick:tick,trackEnd:tick});
  pos=end;
 }
 // canonical tempo map; input sometimes has duplicate tick0 default. latest at same tick wins.
 const tmap=new Map();for(const t of tempos)tmap.set(t.tick,t.usPerQuarter);if(!tmap.size)tmap.set(0,500000);const tempo=[...tmap.entries()].sort((a,b)=>a[0]-b[0]).map(([tick,usPerQuarter])=>({tick,usPerQuarter,bpm:60000000/usPerQuarter}));
 const tsmap=new Map();for(const t of timesigs)tsmap.set(t.tick,t);const timeSignatures=[...tsmap.values()].sort((a,b)=>a.tick-b.tick);
 const endTick=Math.max(...tracks.map(t=>t.notes.length?Math.max(...t.notes.map(n=>n.end)):0));
 function seconds(tick){let t=0;for(let i=0;i<tempo.length;i++){const st=tempo[i].tick,en=i+1<tempo.length?tempo[i+1].tick:Infinity;if(tick<=st)break;const u=Math.min(tick,en)-st;t+=u*tempo[i].usPerQuarter/division/1e6;if(tick<=en)break}return t}
 const summary=tracks.map(t=>{const keys=t.notes.map(n=>n.key),vel=t.notes.map(n=>n.vel),durs=t.notes.map(n=>n.dur);let overlap=1;for(const n of t.notes){let c=1;for(const a of t.notes){if(a!==n&&a.key===n.key&&a.tick<=n.tick&&n.tick<a.end)c++;}overlap=Math.max(overlap,c);}return{index:t.index,name:t.name,channels:t.channels,programChanges:t.programs,programs:[...new Set(t.programs.map(p=>p.program))],notes:t.notes.length,midiMin:keys.length?Math.min(...keys):null,midiMax:keys.length?Math.max(...keys):null,velocityMin:vel.length?Math.min(...vel):null,velocityMax:vel.length?Math.max(...vel):null,durationMinTicks:durs.length?Math.min(...durs):null,durationMaxTicks:durs.length?Math.max(...durs):null,startTick:t.notes.length?Math.min(...t.notes.map(n=>n.tick)):null,endTick:t.notes.length?Math.max(...t.notes.map(n=>n.end)):null,maxSameKeyOverlap:overlap,cc:t.cc,controls:t.controls}});
 const sig=(notes)=>notes.map(n=>[n.tick,n.key,n.dur,n.vel].join(':')).join('|');
 const dup=[];for(let i=0;i<tracks.length;i++)for(let j=i+1;j<tracks.length;j++)if(tracks[i].notes.length&&tracks[i].notes.length===tracks[j].notes.length&&sig(tracks[i].notes)===sig(tracks[j].notes))dup.push([i,j,'exact notes+ticks+durations+velocities']);
 return {file,format,ntracks,division,tempo,timeSignatures,endTick,seconds:seconds(endTick),tracks:summary,duplicates:dup,hashes:{file:crypto.createHash('sha256').update(b).digest('hex')}};
}
for(const f of process.argv.slice(2)){const a=analyze(f);const out=path.join(path.dirname(f),'analysis.json');fs.writeFileSync(out,JSON.stringify(a,null,2)+'\n');console.log(JSON.stringify({file:f,out,format:a.format,division:a.division,tempo:a.tempo,timeSignatures:a.timeSignatures,endTick:a.endTick,seconds:a.seconds,tracks:a.tracks,duplicates:a.duplicates},null,2));}
module.exports={analyze};
