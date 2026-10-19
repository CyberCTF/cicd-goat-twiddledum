# Upstream

This lab reproduces one challenge — **Twiddledum** — from CI/CD Goat.

| What | Source | Licence |
| --- | --- | --- |
| The "Twiddledum" challenge (Dependency Chain Abuse via a mutable git-tag dependency) | [CI/CD Goat](https://github.com/cider-security-research/cicd-goat) by Cider Security (now Palo Alto Networks), v1.2.7 | Apache-2.0 |
| Security class | [OWASP CICD-SEC-3: Dependency Chain Abuse](https://owasp.org/www-project-top-10-ci-cd-security-risks/CICD-SEC-03-Dependency-Chain-Abuse) | — |

Only the *vulnerability* is reproduced, not upstream's eight-machine CI/CD stack. The lab is two
machines — a Jenkins controller and a Gitea git host — which is the minimum this attack needs: a
pipeline that installs a dependency pinned to a mutable git ref, and a repository (the dependency)
the attacker can write to.

Nothing is vendored from upstream. Upstream's `twiddledum` is a copy of the `dedupe` npm package
(MIT) and its `twiddledee` is a throwaway stub, and the pipeline token is one fixed UUID. This lab
instead ships **original** minimal packages (`build/gitea/repo-src/twiddledum/` and
`.../twiddledee/`, authored here, no third-party code) with an original `Jenkinsfile`, and injects a
**per-player** flag into the Jenkins credential store at run time, so each player exfiltrates their
own flag and nothing but the challenge idea comes from upstream.

## The vulnerability, reproduced exactly

`twiddledum`'s `package.json` pins its one dependency to a **git-tag version range**:

```json
"twiddledee": "git+http://gitea:3000/Wonderland/twiddledee#semver:^1.1.0"
```

`#semver:^1.1.0` is a *mutable* reference: npm resolves it by listing `twiddledee`'s git tags and
installing the **highest** one that satisfies the range. The attacker has write access to
`twiddledee`, so by committing a payload and pushing a higher tag (`1.2.0`) they make the range
resolve to their commit — classic dependency chain abuse. The twiddledum pipeline runs
`npm install --ignore-scripts` (so npm lifecycle scripts are a dead end — the same twist upstream
calls out) and then `node index.js`, which `require()`s `twiddledee` and therefore executes the
dependency's module code. The payload reads the pipeline's bound release token and prints it.

## Faithful deviations

Three, each kept as small as possible:

1. **The trigger (as in the White Rabbit lab).** Upstream wires builds with the Jenkins Gitea
   plugin. This lab uses the Jenkins **git** multibranch source with branch discovery and a
   one-minute periodic rescan (an SCM poll, no inbound webhook), dropping a Jenkins↔Gitea plugin
   version dependency for a version-robust git poll — which matters for a lab family meant to run
   unattended. Because the attacker changes the *dependency* and not `twiddledum` itself, the
   consuming build is **triggered manually** after poisoning (the solver does this), exactly as
   upstream's own solution instructs ("Manually trigger the twiddledum pipeline").

2. **The credential shape and exfiltration encoding.** Upstream stores the token as a
   username/password credential and exfiltrates with plain `base64`, and also abuses it a second way
   (writing it into `~/.npmrc` as an npm authToken and running `npm publish`). This lab stores the
   token as a GLOBAL-scope **string** credential bound into the build as `FLAG6`, and keeps a single,
   self-contained exfiltration path: the dependency prints the token. On the modern Jenkins this lab
   ships, the `credentials-binding` plugin masks a bound secret's raw value **and its plain base64**,
   so the plain-base64 trick no longer works; the payload therefore **reverses the value before
   base64-encoding it** (`base64(reverse(FLAG6))`), a transform the masker does not precompute. The
   npm-publish-to-the-public-registry vector is dropped so the lab stays hermetic (no internet is
   required at run time) and focused on the dependency-chain mechanic. This is arguably a truer
   lesson for current CI: masking is a best-effort guardrail, not a control.

3. **Original, minimal packages.** Both repositories are tiny original Node packages rather than
   vendored upstream code; `twiddledee` carries an initial `1.1.0` tag so the range resolves to a
   benign version until the attacker pushes `1.2.0`.
