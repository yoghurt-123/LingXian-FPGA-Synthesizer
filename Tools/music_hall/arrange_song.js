'use strict';
const fs=require('fs'),path=require('path');
const {inspect}=require('./inspect_midi');
const {pianoMap}=require('./compile_song');
const GM_DRUMS={35:0,36:0,38:1,40:1,41:7,43:7,45:7,47:8,48:6,49:5,51:4,52:5,55:5,57:5};
const STRINGS=[40,45,50,55,59,64];
const STRING_NAMES=['E2','A2','D3','G3','B3','E4'];
function guitarPosition(midi){let best=null;for(let s=0;s<6;s++){const fret=midi-STRINGS[s];if(fret>=0&&fret<=12){const cand={string:s,fret};if(!best||fret<best.fret)best=cand;}}if(!best)throw Error('guitar unplayable midi '+midi);return best;}
const CONFIG={
 'music_packs/fight_for_better_future/source.mid':{
  song_id:'fight-for-better-future-cc0',title:'Fight for Better Future [Rock/Metal]',composer:'nene',source_url:'https://opengameart.org/content/fight-for-better-future-rockmetal',midi_url:'https://opengameart.org/sites/default/files/fight_for_better_future.mid',license:'CC0 1.0',duration_tick:84480,
  piano_tracks:[{index:4,transpose:24,role:'Bass +24 semitones (adapted to piano low register)'},{index:6,transpose:0,role:'Synth lead (adapted to piano)'},{index:7,transpose:0,role:'Strings (adapted to piano)'},{index:1,transpose:0,role:'Lead guitar transferred to piano to respect the 3-voice guitar pool; pitch bends omitted'}],
  guitar_tracks:[{index:2,transpose:0,role:'Right rhythm guitar; Left Guitar is an exact duplicate and is not double-triggered'}],
  drum_track:5, sections:8
 },
 'music_packs/rock_music_0/source.mid':{
  song_id:'rock-music-0-cc0',title:'Rock Music',composer:'Umplix',source_url:'https://opengameart.org/content/rock-music-0',midi_url:'https://opengameart.org/sites/default/files/umplixs_rock.mid',license:'CC0 1.0',duration_tick:30720,
  piano_tracks:[],guitar_tracks:[{index:1,transpose:0,role:'Source guitar (track3 is an exact duplicate and is not double-triggered)'}],drum_track:2,sections:2
 }
};
function generate(midPath){
 const cfg=CONFIG[midPath];if(!cfg)throw Error('no config');const m=inspect(midPath);const dir=path.dirname(midPath);const a=JSON.parse(fs.readFileSync(path.join(dir,"analysis.json"),"utf8"));
 const scorePath=path.join(dir,'score','score.json');fs.mkdirSync(path.dirname(scorePath),{recursive:true});
 const pnotes=[];
 for(const spec of cfg.piano_tracks){const t=m.tracks[spec.index];if(!t)throw Error('piano source track '+spec.index);for(const n of t.notes){pnotes.push({start_tick:n.tick,duration_ticks:n.dur,midi:n.key+spec.transpose,velocity:n.vel,source_track:t.name||String(spec.index),source_midi:n.key,adaptation:spec.role});}}
 // Merge same-pitch/same-start duplicates, then clamp each note before the next same key.
 const merged=[];const keyStart=new Map();for(const n of pnotes.sort((a,b)=>a.start_tick-b.start_tick||b.velocity-a.velocity)){const pm=pianoMap(n.midi);if(!pm)throw Error('piano unplayable midi '+n.midi);const k=pm.key+':'+n.start_tick;if(keyStart.has(k)){const old=keyStart.get(k);old.velocity=Math.max(old.velocity,n.velocity);old.duration_ticks=Math.max(old.duration_ticks,n.duration_ticks);old.adaptation+='; same hardware key/start collision merged';continue;}n.piano_key=pm.key;n.piano_octave=pm.octave;keyStart.set(k,n);merged.push(n)}
 const byKey=new Map();for(const n of merged){const pm=pianoMap(n.midi);n.piano_key=pm.key;n.piano_octave=pm.octave;if(!byKey.has(pm.key))byKey.set(pm.key,[]);byKey.get(pm.key).push(n)}
 for(const list of byKey.values()){list.sort((a,b)=>a.start_tick-b.start_tick);for(let i=0;i<list.length;i++){const n=list[i],next=list[i+1];if(next){const gap=next.start_tick-n.start_tick;n.duration_ticks=Math.max(1,Math.min(n.duration_ticks,Math.max(1,gap-48)))}if(n.duration_ticks<=0)n.duration_ticks=1;}}
 const gnotes=[];for(const spec of cfg.guitar_tracks){const t=m.tracks[spec.index];if(!t)throw Error('guitar source '+spec.index);for(const n of t.notes){const midi=n.key+spec.transpose;const pos=guitarPosition(midi);gnotes.push({start_tick:n.tick,duration_ticks:n.dur,string:pos.string,fret:pos.fret,velocity:n.vel,palm:false,technique:'pluck',sustain:'natural_decay',source_track:t.name||String(spec.index),source_midi:n.key,adaptation:spec.role});}}
 const dnotes=[];const t=m.tracks[cfg.drum_track];if(!t)throw Error('drum track');for(const n of t.notes){if(!(n.key in GM_DRUMS))throw Error('unmapped GM drum '+n.key);dnotes.push({tick:n.tick,drum:GM_DRUMS[n.key],velocity:n.vel,source_midi:n.key,adaptation:'GM '+n.key+' -> hardware external '+GM_DRUMS[n.key]});}
 const endTick=cfg.duration_tick;const bar=4*480;const sections=Array.from({length:Math.ceil(endTick/(8*bar))},(_,i)=>({start_bar:i*8+1,end_bar:Math.min((i+1)*8,Math.ceil(endTick/bar)),title:'section '+(i+1)}));
 const score={schema_version:'0.1',song_id:cfg.song_id,title:cfg.title,composer:cfg.composer,rights:cfg.license+'; source '+cfg.source_url+' author '+cfg.composer,content_kind:'licensed-score',source:{name:path.basename(midPath),url:cfg.source_url,author:cfg.composer,license:cfg.license,license_url:'https://creativecommons.org/publicdomain/zero/1.0/',midi_url:cfg.midi_url},ppqn:m.division,time_signature:{numerator:4,denominator:4},tempo_map:[{tick:0,bpm:a.tempo[0].bpm}],duration_ticks:endTick,tracks:[{id:'piano',instrument:'piano',notes:merged,role:'adaptation of bass/synth/strings; see per-note source_track/adaptation'},{id:'guitar',instrument:'guitar',notes:gnotes,role:'source guitars; duplicate layers omitted; lead transposed where required'},{id:'drums',instrument:'drums',hits:dnotes,role:'full source drum track; external hardware map'}],sections,adaptations:['Source duplicate layers are not retriggered; see analysis.json duplicates.','Piano/guitar transfers are adaptations; no extra repeated melody was invented.','Pitch bend, modulation, expression and non-supported CC are preserved only as source metadata, not as FPGA automation.','Crash velocity multiplier remains a hardware limitation.']};
 fs.writeFileSync(scorePath,JSON.stringify(score,null,2)+'\n');
 fs.writeFileSync(path.join(dir,'arrangement_config.json'),JSON.stringify(cfg,null,2)+'\n');
 console.log(JSON.stringify({score:scorePath,piano:merged.length,guitar:gnotes.length,drums:dnotes.length,endTick,tempo:score.tempo_map}));
}
for(const f of Object.keys(CONFIG))generate(f);
