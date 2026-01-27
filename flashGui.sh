#!/bin/bash
# FlashGUI - One-liner deployment
# curl -sL https://yoursite.com/flashgui | bash
# or: curl -sL https://yoursite.com/flashgui | TOKEN=secret bash

set -e

# Setup
INSTALL_DIR="${FLASHGUI_DIR:-/tmp/flashgui-$$}"
PORT="${PORT:-8080}"
TOKEN="${TOKEN:-}"
NO_TUNNEL="${NO_TUNNEL:-false}"

export TOKEN

mkdir -p "$INSTALL_DIR/web"
cd "$INSTALL_DIR"

# Colors
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' B='\033[0;34m' C='\033[0;36m' N='\033[0m' BD='\033[1m'

echo -e "${C}"
echo '  ⚡ FlashGUI - Situational GUI for Linux'
echo -e "${N}"

# Cleanup
cleanup() {
    echo -e "\n${Y}Shutting down...${N}"
    kill $SERVER_PID 2>/dev/null || true
    kill $TUNNEL_PID 2>/dev/null || true
    rm -rf "$INSTALL_DIR"
    echo -e "${G}✓ Cleaned up${N}"
    exit 0
}
trap cleanup SIGINT SIGTERM EXIT

# Write server
cat > server.py << 'PYEOF'
#!/usr/bin/env python3
import os,sys,json,subprocess,signal,mimetypes,hashlib,secrets
from http.server import HTTPServer,BaseHTTPRequestHandler
from urllib.parse import urlparse,parse_qs,unquote
from pathlib import Path
from datetime import datetime
from http.cookies import SimpleCookie

SCRIPT_DIR=Path(__file__).parent.absolute()
WEB_DIR=SCRIPT_DIR/"web"
AUTH_TOKEN=os.environ.get("TOKEN","")
SESSION_SECRET=secrets.token_hex(16)

def make_session(t):return hashlib.sha256(f"{t}:{SESSION_SECRET}".encode()).hexdigest()
def verify_session(c):
    if not AUTH_TOKEN:return True
    if not c:return False
    ck=SimpleCookie();ck.load(c)
    return "session"in ck and ck["session"].value==make_session(AUTH_TOKEN)

class H(BaseHTTPRequestHandler):
    def log_message(self,*a):pass
    def send_json(self,d,s=200):
        self.send_response(s);self.send_header("Content-Type","application/json");self.send_header("Access-Control-Allow-Origin","*");self.end_headers();self.wfile.write(json.dumps(d).encode())
    def do_OPTIONS(self):
        self.send_response(200);self.send_header("Access-Control-Allow-Origin","*");self.send_header("Access-Control-Allow-Methods","GET,POST,OPTIONS");self.send_header("Access-Control-Allow-Headers","Content-Type");self.end_headers()
    def check_auth(self):return not AUTH_TOKEN or verify_session(self.headers.get("Cookie",""))
    def login_page(self):
        h='''<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>FlashGUI</title><style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:system-ui;background:#0f0f0f;color:#e0e0e0;min-height:100vh;display:flex;align-items:center;justify-content:center}.b{background:#1a1a1a;border:1px solid #333;border-radius:12px;padding:2.5rem;width:100%;max-width:360px}.l{text-align:center;margin-bottom:2rem;color:#00d4aa;font-size:1.5rem;font-weight:700}.e{background:#ff555520;border:1px solid #ff5555;color:#ff5555;padding:.75rem;border-radius:6px;margin-bottom:1rem;font-size:.875rem;display:none}.e.s{display:block}input{width:100%;background:#252525;border:1px solid #333;color:#e0e0e0;padding:.875rem 1rem;border-radius:6px;font-size:1rem;margin-bottom:1rem;outline:none}input:focus{border-color:#00d4aa}button{width:100%;background:#00d4aa;border:none;color:#0f0f0f;padding:.875rem;border-radius:6px;font-size:1rem;font-weight:600;cursor:pointer}button:hover{background:#00b894}</style></head><body><div class="b"><div class="l">⚡ FlashGUI</div><div class="e"id="e">Invalid token</div><form id="f"><input type="password"id="t"placeholder="Enter access token"autofocus><button type="submit">Access</button></form></div><script>document.getElementById('f').onsubmit=async e=>{e.preventDefault();const r=await fetch('/api/auth',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({token:document.getElementById('t').value})});r.ok?location.reload():document.getElementById('e').classList.add('s')}</script></body></html>'''
        self.send_response(200);self.send_header("Content-Type","text/html");self.end_headers();self.wfile.write(h.encode())
    def do_GET(self):
        p=urlparse(self.path);path=p.path;q=parse_qs(p.query)
        if AUTH_TOKEN and path not in["/api/auth"]and not self.check_auth():self.login_page();return
        if path=="/api/stats":self.h_stats()
        elif path=="/api/processes":self.h_procs()
        elif path=="/api/files":self.h_files(q)
        elif path=="/api/file":self.h_file(q)
        elif path=="/api/logs":self.h_logs(q)
        elif path=="/api/info":self.h_info()
        else:self.serve(path)
    def do_POST(self):
        p=urlparse(self.path).path;cl=int(self.headers.get("Content-Length",0));b=self.rfile.read(cl).decode()if cl else"{}"
        try:d=json.loads(b)if b else{}
        except:self.send_json({"error":"Invalid JSON"},400);return
        if p=="/api/auth":self.h_auth(d);return
        if AUTH_TOKEN and not self.check_auth():self.send_json({"error":"Unauthorized"},401);return
        if p=="/api/exec":self.h_exec(d)
        elif p=="/api/kill":self.h_kill(d)
        else:self.send_json({"error":"Not found"},404)
    def serve(self,path):
        if path=="/":path="/index.html"
        fp=WEB_DIR/path.lstrip("/")
        try:fp=fp.resolve();assert str(fp).startswith(str(WEB_DIR))
        except:self.send_error(403);return
        if fp.is_file():
            mt,_=mimetypes.guess_type(str(fp));self.send_response(200);self.send_header("Content-Type",mt or"application/octet-stream");self.end_headers()
            with open(fp,"rb")as f:self.wfile.write(f.read())
        else:self.send_error(404)
    def h_info(self):self.send_json({"hostname":os.uname().nodename,"os":f"{os.uname().sysname} {os.uname().release}","arch":os.uname().machine,"user":os.environ.get("USER","unknown"),"time":datetime.now().isoformat()})
    def h_auth(self,d):
        if d.get("token")==AUTH_TOKEN:
            s=make_session(AUTH_TOKEN);self.send_response(200);self.send_header("Content-Type","application/json");self.send_header("Set-Cookie",f"session={s}; Path=/; HttpOnly; SameSite=Strict");self.end_headers();self.wfile.write(b'{"success":true}')
        else:self.send_json({"error":"Invalid"},401)
    def h_stats(self):
        s={}
        try:
            with open("/proc/loadavg")as f:l=f.read().split();s["load"]={"1min":float(l[0]),"5min":float(l[1]),"15min":float(l[2])}
        except:s["load"]=None
        try:
            m={};
            with open("/proc/meminfo")as f:
                for ln in f:p=ln.split();m[p[0].rstrip(":")]=int(p[1])*1024 if len(p)>=2 else 0
            t,a=m.get("MemTotal",0),m.get("MemAvailable",0);u=t-a;s["memory"]={"total":t,"used":u,"available":a,"percent":round((u/t)*100,1)if t else 0}
        except:s["memory"]=None
        try:st=os.statvfs("/");t,f=st.f_blocks*st.f_frsize,st.f_bavail*st.f_frsize;u=t-f;s["disk"]={"total":t,"used":u,"free":f,"percent":round((u/t)*100,1)if t else 0}
        except:s["disk"]=None
        try:
            with open("/proc/uptime")as f:s["uptime"]=int(float(f.read().split()[0]))
        except:s["uptime"]=None
        self.send_json(s)
    def h_procs(self):
        try:
            r=subprocess.run(["ps","aux","--sort=-pcpu"],capture_output=True,text=True,timeout=5);lines=r.stdout.strip().split("\n");procs=[]
            for ln in lines[1:51]:
                p=ln.split(None,10)
                if len(p)>=11:procs.append({"user":p[0],"pid":int(p[1]),"cpu":float(p[2]),"mem":float(p[3]),"stat":p[7],"command":p[10]})
            self.send_json({"processes":procs})
        except Exception as e:self.send_json({"error":str(e)},500)
    def h_files(self,q):
        path=unquote(q.get("path",["/"])[0])
        try:
            p=Path(path).resolve()
            if not p.exists():self.send_json({"error":"Not found"},404);return
            if not p.is_dir():self.send_json({"error":"Not a directory"},400);return
            items=[]
            for i in sorted(p.iterdir()):
                try:st=i.stat();items.append({"name":i.name,"path":str(i),"type":"dir"if i.is_dir()else"file","size":st.st_size if i.is_file()else None,"modified":datetime.fromtimestamp(st.st_mtime).isoformat()})
                except:items.append({"name":i.name,"path":str(i),"type":"unknown","error":"Permission denied"})
            self.send_json({"path":str(p),"parent":str(p.parent)if p!=p.parent else None,"items":items})
        except Exception as e:self.send_json({"error":str(e)},500)
    def h_file(self,q):
        path=q.get("path",[None])[0]
        if not path:self.send_json({"error":"Path required"},400);return
        try:
            p=Path(unquote(path)).resolve()
            if not p.exists():self.send_json({"error":"Not found"},404);return
            if p.stat().st_size>1048576:self.send_json({"error":"Too large"},400);return
            self.send_json({"path":str(p),"content":p.read_text(),"size":p.stat().st_size})
        except Exception as e:self.send_json({"error":str(e)},500)
    def h_logs(self,q):
        n=q.get("name",[None])[0];lines=min(int(q.get("lines",[100])[0]),1000)
        if n:
            lp=f"/var/log/{n}"
            try:r=subprocess.run(["tail","-n",str(lines),lp],capture_output=True,text=True,timeout=5);self.send_json({"name":n,"content":r.stdout})
            except Exception as e:self.send_json({"error":str(e)},500)
        else:
            logs=[]
            for f in["/var/log/syslog","/var/log/messages","/var/log/auth.log","/var/log/kern.log"]:
                if os.path.exists(f):
                    try:logs.append({"name":os.path.basename(f),"path":f,"size":os.path.getsize(f)})
                    except:pass
            try:
                for f in os.listdir("/var/log"):
                    fp=f"/var/log/{f}"
                    if os.path.isfile(fp)and not any(l["path"]==fp for l in logs):
                        try:logs.append({"name":f,"path":fp,"size":os.path.getsize(fp)})
                        except:pass
            except:pass
            self.send_json({"logs":logs})
    def h_exec(self,d):
        cmd=d.get("cmd","")
        if not cmd:self.send_json({"error":"Command required"},400);return
        try:r=subprocess.run(cmd,shell=True,capture_output=True,text=True,timeout=min(d.get("timeout",30),300),cwd=d.get("cwd",os.environ.get("HOME","/")));self.send_json({"stdout":r.stdout,"stderr":r.stderr,"returncode":r.returncode})
        except subprocess.TimeoutExpired:self.send_json({"error":"Timeout"},408)
        except Exception as e:self.send_json({"error":str(e)},500)
    def h_kill(self,d):
        pid=d.get("pid")
        if not pid:self.send_json({"error":"PID required"},400);return
        sig={"TERM":signal.SIGTERM,"KILL":signal.SIGKILL,"HUP":signal.SIGHUP}.get(d.get("signal","TERM"))
        try:os.kill(int(pid),sig);self.send_json({"success":True})
        except Exception as e:self.send_json({"error":str(e)},500)

if __name__=="__main__":
    port=int(sys.argv[1])if len(sys.argv)>1 else 8080
    print(f"FlashGUI server on port {port}")
    HTTPServer(("0.0.0.0",port),H).serve_forever()
PYEOF

# Write index.html (minified)
cat > web/index.html << 'HTMLEOF'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>FlashGUI</title><style>:root{--bg:#0f0f0f;--surface:#1a1a1a;--surface-2:#252525;--border:#333;--text:#e0e0e0;--text-dim:#888;--accent:#00d4aa;--danger:#ff5555;--warning:#ffaa00}*{margin:0;padding:0;box-sizing:border-box}body{font-family:system-ui,sans-serif;background:var(--bg);color:var(--text);min-height:100vh}header{background:var(--surface);border-bottom:1px solid var(--border);padding:1rem 1.5rem;display:flex;align-items:center;justify-content:space-between;position:sticky;top:0;z-index:100}.logo{font-size:1.25rem;font-weight:700;color:var(--accent)}nav{background:var(--surface);border-bottom:1px solid var(--border);display:flex;padding:0 1rem;overflow-x:auto}nav button{background:none;border:none;color:var(--text-dim);padding:.875rem 1.25rem;font-size:.875rem;cursor:pointer;border-bottom:2px solid transparent}nav button:hover{color:var(--text);background:var(--surface-2)}nav button.active{color:var(--accent);border-bottom-color:var(--accent)}main{padding:1.5rem;max-width:1400px;margin:0 auto}.panel{display:none}.panel.active{display:block}.card{background:var(--surface);border:1px solid var(--border);border-radius:8px;padding:1.25rem;margin-bottom:1rem}.card-title{font-size:.75rem;text-transform:uppercase;letter-spacing:.05em;color:var(--text-dim);margin-bottom:.75rem}.stats-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:1rem;margin-bottom:1.5rem}.stat-card{background:var(--surface);border:1px solid var(--border);border-radius:8px;padding:1.25rem}.stat-label{font-size:.75rem;text-transform:uppercase;color:var(--text-dim);margin-bottom:.5rem}.stat-value{font-size:1.75rem;font-weight:600;color:var(--accent)}.progress{height:6px;background:var(--surface-2);border-radius:3px;margin-top:.75rem}.progress-bar{height:100%;background:var(--accent);transition:width .3s}.progress-bar.warning{background:var(--warning)}.progress-bar.danger{background:var(--danger)}table{width:100%;border-collapse:collapse;font-size:.875rem}th,td{text-align:left;padding:.75rem;border-bottom:1px solid var(--border)}th{color:var(--text-dim);font-weight:500;font-size:.75rem;text-transform:uppercase;background:var(--surface-2)}tr:hover td{background:var(--surface-2)}.mono{font-family:'SF Mono',Monaco,monospace;font-size:.8125rem}.terminal{background:#0a0a0a;border:1px solid var(--border);border-radius:8px;overflow:hidden}.terminal-output{padding:1rem;font-family:monospace;font-size:.8125rem;line-height:1.5;max-height:400px;overflow-y:auto;white-space:pre-wrap}.terminal-input-wrapper{display:flex;border-top:1px solid var(--border)}.terminal-prompt{padding:.75rem 1rem;color:var(--accent);font-family:monospace;background:var(--surface-2)}.terminal-input{flex:1;background:transparent;border:none;color:var(--text);padding:.75rem;font-family:monospace;outline:none}.path-bar{display:flex;gap:.5rem;margin-bottom:1rem;flex-wrap:wrap}.path-segment{background:var(--surface-2);border:1px solid var(--border);padding:.375rem .75rem;border-radius:4px;font-size:.8125rem;cursor:pointer}.path-segment:hover{border-color:var(--accent);color:var(--accent)}.file-item{display:flex;align-items:center;gap:.75rem;padding:.625rem .75rem;border-radius:4px;cursor:pointer}.file-item:hover{background:var(--surface-2)}.file-icon{width:20px;text-align:center;color:var(--text-dim)}.file-icon.dir{color:var(--accent)}.file-name{flex:1;font-size:.875rem}.file-meta{font-size:.75rem;color:var(--text-dim)}.btn{background:var(--surface-2);border:1px solid var(--border);color:var(--text);padding:.5rem 1rem;border-radius:6px;font-size:.875rem;cursor:pointer}.btn:hover{border-color:var(--accent);color:var(--accent)}.btn-sm{padding:.25rem .5rem;font-size:.75rem}.btn-danger{border-color:var(--danger);color:var(--danger)}.btn-danger:hover{background:var(--danger);color:var(--bg)}.log-list{display:flex;flex-wrap:wrap;gap:.5rem;margin-bottom:1rem}.log-btn{background:var(--surface-2);border:1px solid var(--border);color:var(--text-dim);padding:.375rem .75rem;border-radius:4px;font-size:.8125rem;cursor:pointer}.log-btn:hover,.log-btn.active{border-color:var(--accent);color:var(--accent)}.log-content{background:#0a0a0a;border:1px solid var(--border);border-radius:8px;padding:1rem;font-family:monospace;font-size:.75rem;line-height:1.6;max-height:500px;overflow:auto;white-space:pre-wrap}.modal{display:none;position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,.8);z-index:200;padding:2rem;overflow:auto}.modal.active{display:flex;align-items:flex-start;justify-content:center}.modal-content{background:var(--surface);border:1px solid var(--border);border-radius:8px;width:100%;max-width:900px;max-height:90vh;overflow:hidden;display:flex;flex-direction:column}.modal-header{display:flex;align-items:center;justify-content:space-between;padding:1rem;border-bottom:1px solid var(--border)}.modal-title{font-size:.875rem;font-weight:500;font-family:monospace}.modal-body{flex:1;overflow:auto;padding:1rem;background:#0a0a0a}.modal-body pre{font-family:monospace;font-size:.8125rem;line-height:1.6;white-space:pre-wrap}.truncate{white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:300px}.text-dim{color:var(--text-dim)}.text-danger{color:var(--danger)}.text-warning{color:var(--warning)}</style></head><body><header><div class="logo">⚡ FlashGUI</div><div id="host-info" class="text-dim"></div></header><nav><button class="active" data-panel="dashboard">Dashboard</button><button data-panel="terminal">Terminal</button><button data-panel="processes">Processes</button><button data-panel="files">Files</button><button data-panel="logs">Logs</button><button onclick="location.href='/desktop.html'" style="margin-left:auto;color:var(--accent)">🖥️ Desktop</button></nav><main><div class="panel active" id="panel-dashboard"><div class="stats-grid"><div class="stat-card"><div class="stat-label">CPU Load</div><div class="stat-value" id="stat-cpu">--</div></div><div class="stat-card"><div class="stat-label">Memory</div><div class="stat-value" id="stat-mem">--</div><div class="progress"><div class="progress-bar" id="mem-bar"></div></div></div><div class="stat-card"><div class="stat-label">Disk</div><div class="stat-value" id="stat-disk">--</div><div class="progress"><div class="progress-bar" id="disk-bar"></div></div></div><div class="stat-card"><div class="stat-label">Uptime</div><div class="stat-value" id="stat-uptime">--</div></div></div><div class="card"><div class="card-title">Quick Terminal</div><div class="terminal"><div class="terminal-output" id="quick-output">Type a command below.\n</div><div class="terminal-input-wrapper"><span class="terminal-prompt">$</span><input type="text" class="terminal-input" id="quick-input" placeholder="Enter command..."></div></div></div><div class="card"><div class="card-title">Top Processes</div><table><thead><tr><th>Command</th><th>PID</th><th>CPU</th><th>MEM</th><th>User</th></tr></thead><tbody id="top-procs"></tbody></table></div></div><div class="panel" id="panel-terminal"><div class="card"><div class="terminal" style="height:70vh"><div class="terminal-output" id="term-output" style="height:calc(100% - 50px)"></div><div class="terminal-input-wrapper"><span class="terminal-prompt">$</span><input type="text" class="terminal-input" id="term-input"></div></div></div></div><div class="panel" id="panel-processes"><div class="card"><div style="display:flex;justify-content:space-between;margin-bottom:1rem"><div class="card-title" style="margin:0">Processes</div><button class="btn btn-sm" onclick="loadProcs()">Refresh</button></div><table><thead><tr><th>Command</th><th>PID</th><th>User</th><th>CPU</th><th>MEM</th><th>Actions</th></tr></thead><tbody id="proc-list"></tbody></table></div></div><div class="panel" id="panel-files"><div class="card"><div class="path-bar" id="path-bar"></div><div id="file-list"></div></div></div><div class="panel" id="panel-logs"><div class="card"><div class="card-title">Logs</div><div class="log-list" id="log-list"></div><div class="log-content" id="log-content">Select a log...</div></div></div></main><div class="modal" id="file-modal"><div class="modal-content"><div class="modal-header"><span class="modal-title" id="modal-name"></span><button class="btn btn-sm" onclick="closeModal()">Close</button></div><div class="modal-body"><pre id="modal-content"></pre></div></div></div><script>let curPath='/';const $=s=>document.getElementById(s),api=async(e,o={})=>(await fetch('/api/'+e,{...o,headers:{'Content-Type':'application/json',...o.headers}})).json(),esc=t=>{const d=document.createElement('div');d.textContent=t;return d.innerHTML},fmtB=b=>{if(!b)return'0 B';const k=1024,s=['B','KB','MB','GB'],i=Math.floor(Math.log(b)/Math.log(k));return(b/Math.pow(k,i)).toFixed(1)+' '+s[i]},fmtUp=s=>{const d=Math.floor(s/86400),h=Math.floor(s%86400/3600),m=Math.floor(s%3600/60);return d>0?d+'d '+h+'h':h>0?h+'h '+m+'m':m+'m'};async function loadInfo(){const i=await api('info');$('host-info').textContent=i.hostname+' • '+i.os}async function loadStats(){const s=await api('stats');if(s.load)$('stat-cpu').textContent=s.load['1min'].toFixed(2);if(s.memory){$('stat-mem').textContent=s.memory.percent+'%';$('mem-bar').style.width=s.memory.percent+'%';$('mem-bar').className='progress-bar'+(s.memory.percent>90?' danger':s.memory.percent>70?' warning':'')}if(s.disk){$('stat-disk').textContent=s.disk.percent+'%';$('disk-bar').style.width=s.disk.percent+'%'}if(s.uptime)$('stat-uptime').textContent=fmtUp(s.uptime)}async function loadProcs(){const d=await api('processes');$('top-procs').innerHTML=d.processes?.slice(0,5).map(p=>`<tr><td class="mono truncate">${esc(p.command)}</td><td class="mono">${p.pid}</td><td class="mono">${p.cpu}%</td><td class="mono">${p.mem}%</td><td class="mono text-dim">${p.user}</td></tr>`).join('')||'';$('proc-list').innerHTML=d.processes?.map(p=>`<tr><td class="mono truncate">${esc(p.command)}</td><td class="mono">${p.pid}</td><td class="mono text-dim">${p.user}</td><td class="mono">${p.cpu}%</td><td class="mono">${p.mem}%</td><td><button class="btn btn-sm btn-danger" onclick="killProc(${p.pid})">Kill</button></td></tr>`).join('')||''}async function killProc(pid){if(confirm('Kill '+pid+'?')){await api('kill',{method:'POST',body:JSON.stringify({pid,signal:'TERM'})});loadProcs()}}let hist=[],hIdx=-1;async function exec(cmd,outId){if(!cmd.trim())return;hist.push(cmd);hIdx=hist.length;const o=$(outId);o.innerHTML+=`<span style="color:var(--accent)">$ ${esc(cmd)}</span>\n`;const r=await api('exec',{method:'POST',body:JSON.stringify({cmd})});if(r.error)o.innerHTML+=`<span style="color:var(--danger)">${esc(r.error)}</span>\n`;else{if(r.stdout)o.innerHTML+=esc(r.stdout);if(r.stderr)o.innerHTML+=`<span style="color:var(--danger)">${esc(r.stderr)}</span>`}o.innerHTML+='\n';o.scrollTop=o.scrollHeight}function setupTerm(inId,outId){const inp=$(inId);inp.onkeydown=e=>{if(e.key==='Enter'){exec(inp.value,outId);inp.value=''}else if(e.key==='ArrowUp'){e.preventDefault();if(hIdx>0)inp.value=hist[--hIdx]}else if(e.key==='ArrowDown'){e.preventDefault();hIdx<hist.length-1?inp.value=hist[++hIdx]:(hIdx=hist.length,inp.value='')}}}async function loadFiles(path){curPath=path;const d=await api('files?path='+encodeURIComponent(path));if(d.error){$('file-list').innerHTML=`<div class="text-danger">${esc(d.error)}</div>`;return}const segs=d.path.split('/').filter(Boolean);let ph=`<span class="path-segment" onclick="loadFiles('/')">/</span>`,bp='';for(const s of segs){bp+='/'+s;ph+=`<span class="path-segment" onclick="loadFiles('${bp}')">${s}</span>`}$('path-bar').innerHTML=ph;const sorted=d.items.sort((a,b)=>a.type==='dir'&&b.type!=='dir'?-1:a.type!=='dir'&&b.type==='dir'?1:a.name.localeCompare(b.name));let fh=d.parent?`<div class="file-item" onclick="loadFiles('${d.parent}')"><span class="file-icon">📁</span><span class="file-name">..</span></div>`:'';for(const i of sorted)fh+=i.type==='dir'?`<div class="file-item" onclick="loadFiles('${i.path}')"><span class="file-icon dir">📁</span><span class="file-name">${esc(i.name)}</span></div>`:`<div class="file-item" onclick="viewFile('${i.path}')"><span class="file-icon">📄</span><span class="file-name">${esc(i.name)}</span><span class="file-meta">${i.size?fmtB(i.size):''}</span></div>`;$('file-list').innerHTML=fh||'<div class="text-dim">Empty</div>'}async function viewFile(path){const d=await api('file?path='+encodeURIComponent(path));$('modal-name').textContent=path;$('modal-content').textContent=d.error?'Error: '+d.error:d.content;$('file-modal').classList.add('active')}function closeModal(){$('file-modal').classList.remove('active')}async function loadLogs(){const d=await api('logs');$('log-list').innerHTML=d.logs?.map(l=>`<button class="log-btn" onclick="showLog('${l.name}')">${l.name}</button>`).join('')||'No logs'}async function showLog(name){document.querySelectorAll('.log-btn').forEach(b=>b.classList.toggle('active',b.textContent===name));$('log-content').textContent='Loading...';const d=await api('logs?name='+encodeURIComponent(name)+'&lines=200');$('log-content').textContent=d.content||d.error||'Empty';$('log-content').scrollTop=$('log-content').scrollHeight}document.querySelectorAll('nav button[data-panel]').forEach(b=>b.onclick=()=>{document.querySelectorAll('nav button').forEach(x=>x.classList.remove('active'));b.classList.add('active');document.querySelectorAll('.panel').forEach(p=>p.classList.remove('active'));$(('panel-'+b.dataset.panel)).classList.add('active');if(b.dataset.panel==='processes')loadProcs();if(b.dataset.panel==='files')loadFiles(curPath);if(b.dataset.panel==='logs')loadLogs()});setupTerm('quick-input','quick-output');setupTerm('term-input','term-output');document.onkeydown=e=>{if(e.key==='Escape')closeModal()};$('file-modal').onclick=e=>{if(e.target.id==='file-modal')closeModal()};loadInfo();loadStats();loadProcs();setInterval(loadStats,5000)</script></body></html>
HTMLEOF

# Write desktop.html (minified)
cat > web/desktop.html << 'DESKEOF'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>FlashGUI Desktop</title><style>:root{--bg:#1a1a2e;--surface:#16213e;--surface-2:#0f3460;--border:#1f4068;--text:#e0e0e0;--text-dim:#888;--accent:#00d4aa}*{margin:0;padding:0;box-sizing:border-box;user-select:none}body{font-family:system-ui;background:linear-gradient(135deg,#1a1a2e,#16213e);color:var(--text);height:100vh;overflow:hidden}.desktop{position:absolute;top:0;left:0;right:0;bottom:48px;padding:20px;display:flex;flex-wrap:wrap;align-content:flex-start;gap:10px}.desktop-icon{width:80px;padding:10px 5px;display:flex;flex-direction:column;align-items:center;gap:6px;border-radius:8px;cursor:pointer}.desktop-icon:hover{background:rgba(255,255,255,.1)}.desktop-icon .icon{font-size:36px}.desktop-icon .label{font-size:11px;text-align:center}.window{position:absolute;background:var(--surface);border:1px solid var(--border);border-radius:8px;box-shadow:0 8px 32px rgba(0,0,0,.4);min-width:300px;min-height:200px;display:flex;flex-direction:column;overflow:hidden}.window.minimized{display:none}.window.maximized{top:0!important;left:0!important;width:100%!important;height:calc(100% - 48px)!important;border-radius:0}.window-header{background:var(--surface-2);padding:10px 12px;display:flex;align-items:center;gap:10px;cursor:move;border-bottom:1px solid var(--border)}.window-title{flex:1;font-size:13px;font-weight:500;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.window-controls{display:flex;gap:8px}.window-btn{width:14px;height:14px;border-radius:50%;border:none;cursor:pointer}.window-btn.close{background:#ff5f56}.window-btn.minimize{background:#ffbd2e}.window-btn.maximize{background:#27ca40}.window-content{flex:1;overflow:auto;background:#0a0a0a}.window-resize{position:absolute;bottom:0;right:0;width:20px;height:20px;cursor:se-resize}.taskbar{position:absolute;bottom:0;left:0;right:0;height:48px;background:rgba(15,15,20,.95);border-top:1px solid var(--border);display:flex;align-items:center;padding:0 10px;gap:4px}.start-btn{width:40px;height:36px;background:var(--accent);border:none;border-radius:6px;cursor:pointer;font-size:18px}.taskbar-divider{width:1px;height:28px;background:var(--border);margin:0 8px}.taskbar-apps{flex:1;display:flex;gap:4px;overflow-x:auto}.taskbar-item{height:36px;padding:0 12px;background:0 0;border:none;border-radius:6px;color:var(--text);font-size:12px;cursor:pointer;display:flex;align-items:center;gap:8px}.taskbar-item:hover{background:rgba(255,255,255,.1)}.taskbar-item.active{background:rgba(0,212,170,.2)}.taskbar-time{padding:0 12px;font-size:12px;color:var(--text-dim)}.start-menu{position:absolute;bottom:58px;left:10px;width:280px;background:rgba(22,33,62,.98);border:1px solid var(--border);border-radius:12px;padding:10px;display:none}.start-menu.show{display:block}.start-menu-item{display:flex;align-items:center;gap:12px;padding:10px 12px;border-radius:8px;cursor:pointer}.start-menu-item:hover{background:rgba(255,255,255,.1)}.start-menu-item .icon{font-size:24px}.start-menu-item .name{font-size:13px;font-weight:500}.term-container{height:100%;display:flex;flex-direction:column;background:#0a0a0a}.term-output{flex:1;padding:12px;font-family:monospace;font-size:13px;line-height:1.5;overflow-y:auto;white-space:pre-wrap}.term-input-line{display:flex;border-top:1px solid var(--border)}.term-prompt{padding:10px 12px;color:var(--accent);font-family:monospace;background:#111}.term-input{flex:1;background:0 0;border:none;color:var(--text);padding:10px;font-family:monospace;outline:none}.stats-widget{padding:15px;display:grid;grid-template-columns:1fr 1fr;gap:15px}.stat-box{background:var(--surface);border-radius:8px;padding:12px}.stat-label{font-size:10px;text-transform:uppercase;color:var(--text-dim);margin-bottom:4px}.stat-value{font-size:24px;font-weight:600;color:var(--accent)}.progress{height:4px;background:var(--surface-2);border-radius:2px;margin-top:8px}.progress-bar{height:100%;background:var(--accent)}.proc-list{padding:10px}.proc-item{display:flex;align-items:center;padding:8px 10px;border-radius:6px;font-size:12px;font-family:monospace}.proc-item:hover{background:var(--surface)}.proc-item .cmd{flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.proc-item .pid{width:60px;color:var(--text-dim)}.proc-item .cpu{width:60px;text-align:right}.proc-item .mem{width:60px;text-align:right;color:var(--text-dim)}.file-browser{padding:10px}.file-path{display:flex;gap:4px;margin-bottom:10px;flex-wrap:wrap}.file-path-seg{background:var(--surface);padding:4px 8px;border-radius:4px;font-size:11px;cursor:pointer}.file-path-seg:hover{background:var(--surface-2)}.file-item{display:flex;align-items:center;gap:10px;padding:8px 10px;border-radius:6px;cursor:pointer;font-size:13px}.file-item:hover{background:var(--surface)}.file-item .icon{width:20px;text-align:center}.file-item .name{flex:1}.file-item .size{font-size:11px;color:var(--text-dim)}</style></head><body><div class="desktop"><div class="desktop-icon" ondblclick="openWin('terminal')"><div class="icon">💻</div><div class="label">Terminal</div></div><div class="desktop-icon" ondblclick="openWin('stats')"><div class="icon">📊</div><div class="label">Stats</div></div><div class="desktop-icon" ondblclick="openWin('processes')"><div class="icon">⚙️</div><div class="label">Processes</div></div><div class="desktop-icon" ondblclick="openWin('files')"><div class="icon">📁</div><div class="label">Files</div></div><div class="desktop-icon" ondblclick="openWin('logs')"><div class="icon">📜</div><div class="label">Logs</div></div><div class="desktop-icon" ondblclick="location.href='/'"><div class="icon">📋</div><div class="label">Dashboard</div></div></div><div class="taskbar"><button class="start-btn" onclick="toggleStart()">⚡</button><div class="taskbar-divider"></div><div class="taskbar-apps" id="taskbar-apps"></div><div class="taskbar-time" id="clock"></div></div><div class="start-menu" id="start-menu"><div class="start-menu-item" onclick="openWin('terminal');toggleStart()"><div class="icon">💻</div><div class="name">Terminal</div></div><div class="start-menu-item" onclick="openWin('stats');toggleStart()"><div class="icon">📊</div><div class="name">Stats</div></div><div class="start-menu-item" onclick="openWin('processes');toggleStart()"><div class="icon">⚙️</div><div class="name">Processes</div></div><div class="start-menu-item" onclick="openWin('files');toggleStart()"><div class="icon">📁</div><div class="name">Files</div></div><div class="start-menu-item" onclick="openWin('logs');toggleStart()"><div class="icon">📜</div><div class="name">Logs</div></div></div><script>let wins={},winZ=100,activeWin=null;const cfg={terminal:{title:'💻 Terminal',w:700,h:450},stats:{title:'📊 Stats',w:400,h:350},processes:{title:'⚙️ Processes',w:650,h:450},files:{title:'📁 Files',w:550,h:400},logs:{title:'📜 Logs',w:600,h:400}},api=async(e,o={})=>(await fetch('/api/'+e,{...o,headers:{'Content-Type':'application/json'}})).json(),esc=t=>{const d=document.createElement('div');d.textContent=t;return d.innerHTML},fmtB=b=>{if(!b)return'0 B';const k=1024,s=['B','KB','MB','GB'],i=Math.floor(Math.log(b)/Math.log(k));return(b/Math.pow(k,i)).toFixed(1)+' '+s[i]},fmtUp=s=>{const d=Math.floor(s/86400),h=Math.floor(s%86400/3600),m=Math.floor(s%3600/60);return d?d+'d '+h+'h':h?h+'h '+m+'m':m+'m'};function createWin(type){const c=cfg[type],id='win-'+type+'-'+Date.now(),w=document.createElement('div');w.className='window';w.id=id;w.dataset.type=type;w.style.cssText=`width:${c.w}px;height:${c.h}px;left:${100+Object.keys(wins).length*30}px;top:${80+Object.keys(wins).length*30}px;z-index:${++winZ}`;w.innerHTML=`<div class="window-header"><span class="window-title">${c.title}</span><div class="window-controls"><button class="window-btn minimize" onclick="minWin('${id}')"></button><button class="window-btn maximize" onclick="maxWin('${id}')"></button><button class="window-btn close" onclick="closeWin('${id}')"></button></div></div><div class="window-content" id="${id}-content"></div><div class="window-resize"></div>`;document.body.appendChild(w);wins[id]={type,min:false,max:false};makeDrag(w);makeResize(w);w.onmousedown=()=>focusWin(id);loadContent(id,type);updateTaskbar();focusWin(id);return id}function openWin(type){createWin(type)}function closeWin(id){document.getElementById(id)?.remove();delete wins[id];updateTaskbar()}function minWin(id){const w=document.getElementById(id);if(w){w.classList.add('minimized');wins[id].min=true;updateTaskbar()}}function maxWin(id){const w=document.getElementById(id);if(w){w.classList.toggle('maximized');wins[id].max=!wins[id].max}}function focusWin(id){const w=document.getElementById(id);if(w){w.style.zIndex=++winZ;w.classList.remove('minimized');wins[id].min=false;activeWin=id;updateTaskbar()}}function makeDrag(w){const h=w.querySelector('.window-header');let drag=false,sX,sY,sL,sT;h.onmousedown=e=>{if(e.target.classList.contains('window-btn')||wins[w.id]?.max)return;drag=true;sX=e.clientX;sY=e.clientY;sL=w.offsetLeft;sT=w.offsetTop;document.onmousemove=e=>{if(drag){w.style.left=sL+e.clientX-sX+'px';w.style.top=sT+e.clientY-sY+'px'}};document.onmouseup=()=>{drag=false;document.onmousemove=null}}}function makeResize(w){const h=w.querySelector('.window-resize');let rs=false,sX,sY,sW,sH;h.onmousedown=e=>{if(wins[w.id]?.max)return;rs=true;sX=e.clientX;sY=e.clientY;sW=w.offsetWidth;sH=w.offsetHeight;document.onmousemove=e=>{if(rs){w.style.width=Math.max(300,sW+e.clientX-sX)+'px';w.style.height=Math.max(200,sH+e.clientY-sY)+'px'}};document.onmouseup=()=>{rs=false;document.onmousemove=null};e.preventDefault()}}function updateTaskbar(){const c=document.getElementById('taskbar-apps');c.innerHTML='';for(const[id,w]of Object.entries(wins)){const b=document.createElement('button');b.className='taskbar-item'+(id===activeWin&&!w.min?' active':'');b.innerHTML=cfg[w.type].title;b.onclick=()=>focusWin(id);c.appendChild(b)}}async function loadContent(id,type){const c=document.getElementById(id+'-content');if(type==='terminal')loadTerm(c,id);else if(type==='stats')loadStats(c,id);else if(type==='processes')loadProcs(c,id);else if(type==='files')loadFiles(c,id,'/');else if(type==='logs')loadLogs(c,id)}function loadTerm(c,wid){c.innerHTML=`<div class="term-container"><div class="term-output" id="${wid}-out">Welcome to FlashGUI.\n\n</div><div class="term-input-line"><span class="term-prompt">$</span><input type="text" class="term-input" id="${wid}-in"></div></div>`;const inp=document.getElementById(wid+'-in'),out=document.getElementById(wid+'-out');let hist=[],hIdx=-1;inp.onkeydown=async e=>{if(e.key==='Enter'){const cmd=inp.value.trim();if(!cmd)return;hist.push(cmd);hIdx=hist.length;inp.value='';out.innerHTML+=`<span style="color:var(--accent)">$ ${esc(cmd)}</span>\n`;const r=await api('exec',{method:'POST',body:JSON.stringify({cmd})});if(r.error)out.innerHTML+=`<span style="color:#ff5555">${esc(r.error)}</span>\n`;else{if(r.stdout)out.innerHTML+=esc(r.stdout);if(r.stderr)out.innerHTML+=`<span style="color:#ff5555">${esc(r.stderr)}</span>`}out.innerHTML+='\n';out.scrollTop=out.scrollHeight}else if(e.key==='ArrowUp'){e.preventDefault();if(hIdx>0)inp.value=hist[--hIdx]}else if(e.key==='ArrowDown'){e.preventDefault();hIdx<hist.length-1?inp.value=hist[++hIdx]:(hIdx=hist.length,inp.value='')}};inp.focus()}async function loadStats(c,wid){c.innerHTML=`<div class="stats-widget" id="${wid}-stats">Loading...</div>`;const refresh=async()=>{const s=await api('stats'),el=document.getElementById(wid+'-stats');if(!el)return;el.innerHTML=`<div class="stat-box"><div class="stat-label">CPU</div><div class="stat-value">${s.load?s.load['1min'].toFixed(2):'--'}</div></div><div class="stat-box"><div class="stat-label">Memory</div><div class="stat-value">${s.memory?s.memory.percent+'%':'--'}</div><div class="progress"><div class="progress-bar" style="width:${s.memory?.percent||0}%"></div></div></div><div class="stat-box"><div class="stat-label">Disk</div><div class="stat-value">${s.disk?s.disk.percent+'%':'--'}</div><div class="progress"><div class="progress-bar" style="width:${s.disk?.percent||0}%"></div></div></div><div class="stat-box"><div class="stat-label">Uptime</div><div class="stat-value">${s.uptime?fmtUp(s.uptime):'--'}</div></div>`};refresh();const iv=setInterval(()=>{if(!document.getElementById(wid+'-stats'))return clearInterval(iv);refresh()},3000)}async function loadProcs(c,wid){c.innerHTML=`<div class="proc-list" id="${wid}-procs">Loading...</div>`;const refresh=async()=>{const d=await api('processes'),el=document.getElementById(wid+'-procs');if(!el)return;el.innerHTML=d.processes?.slice(0,30).map(p=>`<div class="proc-item"><span class="pid">${p.pid}</span><span class="cmd" title="${esc(p.command)}">${esc(p.command)}</span><span class="cpu" style="color:${p.cpu>50?'#ff5555':p.cpu>20?'#ffaa00':'var(--accent)'}">${p.cpu}%</span><span class="mem">${p.mem}%</span></div>`).join('')||'None'};refresh();const iv=setInterval(()=>{if(!document.getElementById(wid+'-procs'))return clearInterval(iv);refresh()},5000)}async function loadFiles(c,wid,path){c.innerHTML=`<div class="file-browser" id="${wid}-files">Loading...</div>`;c.dataset.path=path;const d=await api('files?path='+encodeURIComponent(path)),el=document.getElementById(wid+'-files');if(d.error){el.innerHTML=`<div style="color:#ff5555;padding:20px">${d.error}</div>`;return}const segs=d.path.split('/').filter(Boolean);let ph=`<span class="file-path-seg" onclick="navFiles('${wid}','/')">/</span>`,bp='';for(const s of segs){bp+='/'+s;ph+=`<span class="file-path-seg" onclick="navFiles('${wid}','${bp}')">${s}</span>`}const sorted=d.items.sort((a,b)=>a.type==='dir'&&b.type!=='dir'?-1:a.type!=='dir'&&b.type==='dir'?1:a.name.localeCompare(b.name));let fh=d.parent?`<div class="file-item" onclick="navFiles('${wid}','${d.parent}')"><span class="icon">📁</span><span class="name">..</span></div>`:'';for(const i of sorted)fh+=i.type==='dir'?`<div class="file-item" onclick="navFiles('${wid}','${i.path}')"><span class="icon">📁</span><span class="name">${esc(i.name)}</span></div>`:`<div class="file-item"><span class="icon">📄</span><span class="name">${esc(i.name)}</span><span class="size">${i.size?fmtB(i.size):''}</span></div>`;el.innerHTML=`<div class="file-path">${ph}</div>${fh}`}function navFiles(wid,path){const c=document.getElementById(wid+'-content');loadFiles(c,wid,path)}async function loadLogs(c,wid){c.innerHTML=`<div style="display:flex;flex-direction:column;height:100%"><div id="${wid}-btns" style="padding:10px;display:flex;flex-wrap:wrap;gap:5px"></div><div id="${wid}-log" style="flex:1;overflow:auto;padding:10px;font-family:monospace;font-size:11px;white-space:pre-wrap;background:#050505">Select log...</div></div>`;const d=await api('logs'),btns=document.getElementById(wid+'-btns');btns.innerHTML=d.logs?.map(l=>`<button onclick="showLog('${wid}','${l.name}')" style="background:var(--surface);border:1px solid var(--border);color:var(--text);padding:4px 10px;border-radius:4px;cursor:pointer;font-size:11px">${l.name}</button>`).join('')||'No logs'}async function showLog(wid,name){const c=document.getElementById(wid+'-log');c.textContent='Loading...';const d=await api('logs?name='+encodeURIComponent(name)+'&lines=200');c.textContent=d.content||d.error||'Empty';c.scrollTop=c.scrollHeight}function toggleStart(){document.getElementById('start-menu').classList.toggle('show')}document.onclick=e=>{if(!e.target.closest('.start-menu')&&!e.target.closest('.start-btn'))document.getElementById('start-menu').classList.remove('show')};function updateClock(){document.getElementById('clock').textContent=new Date().toLocaleTimeString([],{hour:'2-digit',minute:'2-digit'})}updateClock();setInterval(updateClock,1000);api('info').then(i=>document.title='FlashGUI - '+i.hostname)</script></body></html>
DESKEOF

echo -e "${G}✓${N} Files created"

# Check Python
command -v python3 &>/dev/null || { echo -e "${R}✗ Python 3 required${N}"; exit 1; }
echo -e "${G}✓${N} Python 3 found"

# Install cloudflared if needed
if [ "$NO_TUNNEL" != "true" ]; then
    if ! command -v cloudflared &>/dev/null && [ ! -x "$INSTALL_DIR/.bin/cloudflared" ]; then
        echo -e "${Y}↓ Installing cloudflared...${N}"
        ARCH=$(uname -m)
        case $ARCH in
            x86_64) CF_ARCH="amd64" ;;
            aarch64) CF_ARCH="arm64" ;;
            armv7l) CF_ARCH="arm" ;;
            *) echo -e "${R}✗ Unsupported arch${N}"; exit 1 ;;
        esac
        mkdir -p "$INSTALL_DIR/.bin"
        curl -sL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}" -o "$INSTALL_DIR/.bin/cloudflared"
        chmod +x "$INSTALL_DIR/.bin/cloudflared"
        echo -e "${G}✓${N} cloudflared installed"
    fi
    CLOUDFLARED=$(command -v cloudflared || echo "$INSTALL_DIR/.bin/cloudflared")
fi

# Auth status
[ -n "$TOKEN" ] && echo -e "${G}✓${N} Auth enabled" || echo -e "${Y}!${N} No auth (use TOKEN=xxx)"

# Start server
echo -e "${B}◉${N} Starting server..."
python3 server.py $PORT &
SERVER_PID=$!
sleep 1

if ! kill -0 $SERVER_PID 2>/dev/null; then
    echo -e "${R}✗ Server failed${N}"
    exit 1
fi
echo -e "${G}✓${N} Server running on :$PORT"

# Tunnel or local
if [ -n "$CLOUDFLARED" ] && [ "$NO_TUNNEL" != "true" ]; then
    echo -e "${B}◉${N} Starting tunnel..."
    echo ""
    echo -e "  ${BD}Local:${N} http://localhost:$PORT"
    echo -e "  ${BD}Desktop:${N} http://localhost:$PORT/desktop.html"
    echo ""
    echo -e "  ${Y}Tunnel URL below...${N}"
    echo ""
    $CLOUDFLARED tunnel --url http://localhost:$PORT 2>&1 &
    TUNNEL_PID=$!
else
    echo ""
    echo -e "  ${C}🌐 http://localhost:$PORT${N}"
    echo -e "  ${C}🖥️  http://localhost:$PORT/desktop.html${N}"
    echo ""
fi

wait
