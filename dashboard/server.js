// avensio e2e — test runs viewer (gallery + captions + lightbox + YT state badges).
// Pure Node (no deps). Serves index.html, /api/runs (JSON), /file/<rel> (raw).
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = process.env.RUNS_ROOT || 'C:\\Users\\rosa\\_rsm\\__automata\\runs';
const HERE = __dirname;
const AUTH = process.env.AUTH_ENV || 'C:\\Users\\rosa\\_rsm\\__automata\\config\\auth.env';
const PORT = parseInt(process.env.PORT || '8088', 10);
const HOST = process.env.BIND || '0.0.0.0';
const NETBIRD = process.env.NETBIRD_IP || '100.54.7.101';

const MIME = { '.png':'image/png','.jpg':'image/jpeg','.jpeg':'image/jpeg','.gif':'image/gif','.svg':'image/svg+xml',
  '.txt':'text/plain; charset=utf-8','.log':'text/plain; charset=utf-8','.md':'text/plain; charset=utf-8',
  '.json':'application/json; charset=utf-8','.ndjson':'text/plain; charset=utf-8','.html':'text/html; charset=utf-8' };
const isImg = n => /\.(png|jpe?g|gif|svg)$/i.test(n);
const norm = p => path.normalize(p);

function loadAuth(){
  try { const o={}; for(const ln of fs.readFileSync(AUTH,'utf8').split(/\r?\n/)){const t=ln.trim();
    if(!t||t.startsWith('#')||!t.includes('='))continue; const i=t.indexOf('='); o[t.slice(0,i).trim()]=t.slice(i+1).trim();} return o; }
  catch { return {}; }
}
const A = loadAuth();

// --- YouTrack state cache (per issue), best-effort ---
const stateCache = new Map(); // issue -> {state, ts}
async function ytState(issue){
  const now = Date.now();
  const c = stateCache.get(issue);
  if (c && now - c.ts < 30000) return c.state;
  let state = null;
  try {
    if (typeof fetch === 'function' && A.YOUTRACK_BASE_URL && A.YOUTRACK_TOKEN){
      const url = `${A.YOUTRACK_BASE_URL.replace(/\/$/,'')}/api/issues/${issue}?fields=tags(name)`;
      const r = await fetch(url, { headers:{ Authorization:`Bearer ${A.YOUTRACK_TOKEN}`, Accept:'application/json' }});
      if (r.ok){ const j = await r.json();
        const tag = (j.tags||[]).map(t=>t.name).find(n=>/^state:/.test(n));
        if (tag) state = tag.split(':')[1];
      }
    }
  } catch {}
  stateCache.set(issue, { state, ts: now });
  return state;
}

function walk(dir, rel, out){
  let ents; try { ents = fs.readdirSync(dir,{withFileTypes:true}); } catch { return; }
  const imgs=[], files=[];
  for (const e of ents){
    if (e.isDirectory()) walk(path.join(dir,e.name), rel?rel+'/'+e.name:e.name, out);
    else if (isImg(e.name)) imgs.push(e.name);
    else files.push(e.name);
  }
  if (imgs.length){
    const key = rel || '.';
    const shotInfo = imgs.map(n=>{ let mt=0; try{mt=fs.statSync(path.join(dir,n)).mtimeMs;}catch{}
      return { name:n, path:(rel?rel+'/':'')+n, mtime:mt }; })
      .sort((a,b)=> a.name.localeCompare(b.name,undefined,{numeric:true}));
    const fileInfo = files.map(n=>({ name:n, path:(rel?rel+'/':'')+n }));
    const seg = key.split('/');
    const issue = (seg[0].match(/^AVE-\d+/)||[])[0] || null;
    const label = key==='.' ? '(host captures)' : seg.join(' · ');
    const newest = Math.max(...shotInfo.map(s=>s.mtime), 0);
    out.push({ key, label, issue, shots:shotInfo, files:fileInfo, newest });
  }
}

function fmtWhen(ms){ if(!ms) return ''; const d=new Date(ms);
  const p=n=>String(n).padStart(2,'0'); return `${p(d.getDate())}.${p(d.getMonth()+1)}. ${p(d.getHours())}:${p(d.getMinutes())}`; }

const server = http.createServer(async (req,res)=>{
  const u = decodeURIComponent(req.url.split('?')[0]);
  try {
    if (u === '/' || u === '/index.html'){
      res.writeHead(200,{'Content-Type':'text/html; charset=utf-8'});
      return res.end(fs.readFileSync(path.join(HERE,'index.html')));
    }
    if (u === '/api/runs'){
      const out=[]; walk(ROOT,'',out);
      out.sort((a,b)=> b.newest - a.newest);
      const issues=[...new Set(out.map(r=>r.issue).filter(Boolean))];
      const states={}; await Promise.all(issues.map(async i=>{ states[i]=await ytState(i); }));
      const runs = out.map(r=>({ key:r.key, label:r.label, state: r.issue?states[r.issue]:null,
        when: fmtWhen(r.newest), shots:r.shots.map(s=>({name:s.name,path:s.path})), files:r.files }));
      res.writeHead(200,{'Content-Type':'application/json; charset=utf-8'});
      return res.end(JSON.stringify({ root:ROOT, netbird:`${NETBIRD}:${PORT}`, runs }));
    }
    if (u.startsWith('/file/')){
      const rel = u.slice('/file/'.length);
      const abs = norm(path.join(ROOT, rel));
      if (!abs.startsWith(norm(ROOT))){ res.writeHead(403); return res.end('forbidden'); }
      if (!fs.existsSync(abs)){ res.writeHead(404); return res.end('not found'); }
      const ext = path.extname(abs).toLowerCase();
      res.writeHead(200,{'Content-Type':MIME[ext]||'application/octet-stream'});
      return fs.createReadStream(abs).pipe(res);
    }
    res.writeHead(404); res.end('not found');
  } catch(e){ res.writeHead(500); res.end(String(e)); }
});
server.listen(PORT, HOST, ()=> console.log(`viewer up: http://${NETBIRD}:${PORT}/  (bind ${HOST}:${PORT}, root ${ROOT})`));
