'use strict';
// Minimal static server for local/LAN music-hall testing. No public endpoint is claimed.
const http=require('http'),fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'../..');
const server=http.createServer((req,res)=>{
  const rel=decodeURIComponent((req.url||'/').split('?')[0]).replace(/^\/+/,'');
  const file=path.resolve(root,rel);
  if(!file.startsWith(root+path.sep)){res.writeHead(403);return res.end('forbidden');}
  fs.stat(file,(e,st)=>{if(e||!st.isFile()){res.writeHead(404);return res.end('not found');}
    res.writeHead(200,{'Content-Type':file.endsWith('.json')?'application/json':'application/octet-stream','Content-Length':st.size});
    fs.createReadStream(file).pipe(res);});
});
const port=Number(process.env.PORT||8081);
server.listen(port,'0.0.0.0',()=>console.log(`music hall static server: http://127.0.0.1:${port}/music_packs/catalog.json`));
