#!/bin/sh
# Isoloom `setup` step for the Gitea machine (runs once, after Gitea is healthy, in the Gitea image,
# sharing its network namespace so Gitea is reachable at 127.0.0.1:3000). It provisions Wonderland's
# two PUBLIC repositories over the Gitea API and pushes the baked sample projects:
#   - org `Wonderland`
#   - `alice` (the attacker) with WRITE access to the DEPENDENCY repo (twiddledee)
#   - `twiddledum` (public): the consuming Node app whose Jenkins pipeline builds on Jenkins
#   - `twiddledee` (public): the dependency, pushed with an initial `1.1.0` tag so the consumer's
#     `#semver:^1.1.0` range resolves to a benign version until the attacker pushes a higher tag
# No challenge secret is handled here; the flag is a Jenkins credential injected elsewhere.
set -eu

BASE="${GITEA_BASE_URL:-http://127.0.0.1:3000}"
ADMIN_USER="${GITEA_ADMIN_USER:-wonderland_admin}"
ADMIN_PASS="${GITEA_ADMIN_PASS:-W0nderland-admin}"
ORG="Wonderland"
SRC="${TW_SRC:-/opt/repo-src}"

ATTACKER_USER="alice"
ATTACKER_PASS="alice"

AUTH="$ADMIN_USER:$ADMIN_PASS"
API="$BASE/api/v1"

log() { echo "seed: $1"; }

# POST/PUT JSON as admin; tolerate 'already exists' (409/422) so the job is idempotent on restart.
api() {  # method path json
  if [ -n "${3:-}" ]; then
    code=$(curl -s -o /tmp/seed.out -w '%{http_code}' -X "$1" \
           -H 'Content-Type: application/json' -u "$AUTH" \
           --data "$3" "$API$2" 2>/dev/null || echo 000)
  else
    code=$(curl -s -o /tmp/seed.out -w '%{http_code}' -X "$1" -u "$AUTH" "$API$2" 2>/dev/null || echo 000)
  fi
  case "$code" in
    2*) return 0 ;;
    409|422) log "exists ($code): $1 $2"; return 0 ;;
    *) log "WARN $code: $1 $2 -> $(tr -d '\n' < /tmp/seed.out | cut -c1-200)"; return 1 ;;
  esac
}

# push_repo NAME [tag]: initialize the staged source as a fresh repo and push main (+ an optional
# annotated-free tag) to Gitea with the admin's credentials.
push_repo() {
  name="$1"; tag="${2:-}"
  WORK="$(mktemp -d)"
  cp -a "$SRC/$name/." "$WORK/"
  cd "$WORK"
  export GIT_TERMINAL_PROMPT=0 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME="Wonderland Admin" GIT_AUTHOR_EMAIL="admin@wonderland.example"
  export GIT_COMMITTER_NAME="Wonderland Admin" GIT_COMMITTER_EMAIL="admin@wonderland.example"
  export GIT_AUTHOR_DATE="2024-02-01T09:00:00" GIT_COMMITTER_DATE="2024-02-01T09:00:00"
  git -c init.defaultBranch=main init -q
  git add -A
  git commit -q -m "Initial import of the $name package"
  [ -n "$tag" ] && git tag "$tag"
  PUSH_URL="http://$ADMIN_USER:$ADMIN_PASS@127.0.0.1:3000/$ORG/$name.git"
  git push -q "$PUSH_URL" main
  [ -n "$tag" ] && git push -q "$PUSH_URL" "$tag"
  cd /
  rm -rf "$WORK"
  log "$name pushed (main${tag:+ + tag $tag})"
}

# 1. Wait for the Gitea API.
i=0
while :; do
  c=$(curl -s -o /dev/null -w '%{http_code}' "$API/version" 2>/dev/null || echo 000)
  [ "$c" = "200" ] && break
  i=$((i+1)); [ "$i" -lt 120 ] || { log "FATAL: Gitea API never answered"; exit 1; }
  sleep 2
done
log "Gitea API is up"

# 2. Idempotency: if twiddledum already has a main branch, everything below is already done.
c=$(curl -s -o /dev/null -w '%{http_code}' -u "$AUTH" "$API/repos/$ORG/twiddledum/branches/main" 2>/dev/null || echo 000)
if [ "$c" = "200" ]; then
  log "twiddle repositories already seeded; nothing to do"
  exit 0
fi

# 3. Org, attacker user, repositories (both public).
api POST "/orgs" "{\"username\":\"$ORG\",\"visibility\":\"public\"}"
api POST "/admin/users" "{\"username\":\"$ATTACKER_USER\",\"email\":\"alice@wonderland.example\",\"password\":\"$ATTACKER_PASS\",\"must_change_password\":false}"
api POST "/orgs/$ORG/repos" "{\"name\":\"twiddledee\",\"private\":false,\"auto_init\":false,\"default_branch\":\"main\"}"
api POST "/orgs/$ORG/repos" "{\"name\":\"twiddledum\",\"private\":false,\"auto_init\":false,\"default_branch\":\"main\"}"

# 4. Access: alice writes the DEPENDENCY (twiddledee) — the attacker's foothold. She has no access
#    to twiddledum itself; the attack is entirely through the dependency she controls.
api PUT "/repos/$ORG/twiddledee/collaborators/$ATTACKER_USER" "{\"permission\":\"write\"}"

# 5. Push the baked sample projects. twiddledee carries its initial 1.1.0 tag so the consumer's
#    `#semver:^1.1.0` range has a benign version to resolve to before the attack.
push_repo twiddledee 1.1.0
push_repo twiddledum

log "twiddle seeded: public twiddledum + twiddledee (tag 1.1.0), alice=write on twiddledee"
