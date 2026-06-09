# Agent Development Guide

This file is for Codex agents and human contributors working in this repository.
Keep changes public-safe by default: assume anything committed may be pushed to
the public `MapofAgents` repository.

## Project Shape

- `Sources/MapofAgentsCore`: runtime models, persistence, Codex App Server
  clients, supervisor logic, workflow events, and host/runtime stores.
- `Sources/MapofAgentsUI`: SwiftUI canvas, controls, rails, panels, and thread
  reading surfaces.
- `Sources/MapofAgentsApp`: app entry points and platform-level coordination.
- `Tests/MapofAgentsCoreTests`: focused unit and integration-style tests.
- `script/`: local build, runtime diagnostic, iOS, and app-server helper scripts.
- `examples/`: sample configuration only. Do not put private config here.

Use `MapofAgents` naming for new code, files, docs, and tests. Do not reintroduce
legacy project names.

## Development Commands

Use these from the repository root:

```sh
swift build
swift test
./script/runtime_diagnostic.py
./script/build_and_run.sh --verify
```

For iOS project generation and build checks:

```sh
script/ios_doctor.sh
script/ios_project.sh
script/build_ios.sh sim
```

The real Codex App Server integration test is opt-in:

```sh
MAPOFAGENTS_CODEX_INTEGRATION=1 swift test --filter codexAppServerClientConnectsWhenIntegrationEnabled
```

## Privacy Rules

Do not commit personal or machine-specific information. This includes:

- Real usernames, home-directory paths, workspace paths, or external drive names.
- Real machine names, LAN hostnames, tailnet hostnames, SSH aliases, or device IDs.
- Private, LAN, or tailnet IP addresses and hardcoded ports.
- Bearer tokens, API keys, passwords, cookies, SSH keys, pairing tokens, or
  generated authentication material.
- Local Codex account state, thread history, app-server runtime folders, or
  `.codex/` contents.
- Screenshots, GIFs, videos, logs, or reports that reveal private paths,
  endpoints, machine names, account identifiers, or tokens.

Use placeholders such as `example-host.local`, `127.0.0.1`, `<host>`, `<port>`,
`<token>`, and `/Users/example/...` in docs and tests. Keep sample configuration
under `examples/`, and make sure it is fake, minimal, and documented.

Public media assets belong under `docs/assets/` and must be reviewed like code.
Only add screenshots or recordings that are intentionally public-safe.

## Before Committing

Check the exact diff and file list:

```sh
git status --short
git diff --stat
git diff --cached --stat
git diff --cached
```

Run a sensitive-string scan before any public commit or force-push:

```sh
rg -n --hidden --glob '!.git/**' --glob '!.build/**' --glob '!.swiftpm/**' \
  --glob '!.codex/**' \
  '(/Users/[A-Za-z0-9._-]+|/Volumes/[^[:space:]]+|BEGIN .*PRIVATE KEY|OPENAI_API_KEY|api[_-]?key|bearer|password|secret|token|ssh-rsa|ssh-ed25519|github_pat_|ghp_)'

rg -n --hidden --glob '!.git/**' --glob '!.build/**' --glob '!.swiftpm/**' \
  --glob '!.codex/**' \
  '((10|127|192\\.168)\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}|172\\.(1[6-9]|2[0-9]|3[0-1])\\.[0-9]{1,3}\\.[0-9]{1,3}|100\\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\\.[0-9]{1,3}\\.[0-9]{1,3}|https?://[^[:space:]]+:[0-9]{2,5}|wss?://[^[:space:]]+:[0-9]{2,5})'
```

Review every hit. Some matches may be acceptable fake fixtures, placeholder
tokens, or loopback examples, but do not assume.

For media changes, list assets and inspect anything new or modified:

```sh
git diff --cached --name-only -- docs assets
find docs/assets -maxdepth 1 -type f -print
```

## Commit And Push With Approval

Agents may prepare a commit when the user asks for it, but should only push to
GitHub after the user explicitly approves the commit scope.

Before asking for approval, summarize:

- Files changed.
- Tests or checks run.
- Sensitive-string scan results.
- Whether the commit will be a normal follow-up commit or folded into the
  initial release history.

For a normal approved commit:

```sh
git status --short
git add <files>
git commit -m "<message>"
git push origin main
```

After pushing, verify the branch state:

```sh
git status --short --branch
git log --oneline --decorate --max-count=5
```

## Commit History

This repository is currently being prepared as a clean public release. When the
owner asks to keep everything in the initial release, fold changes into the
single root commit instead of adding follow-up commits:

```sh
git add <files>
git commit --amend --no-edit
git push --force-with-lease origin main
```

If local history has accumulated extra commits during release prep, squash them
back into the root only when explicitly requested:

```sh
root=$(git rev-list --max-parents=0 HEAD)
git reset --soft "$root"
git commit --amend --no-edit
git push --force-with-lease origin main
```

After rewriting release history, verify:

```sh
git status --short --branch
git rev-list --count HEAD
git log --oneline --decorate --max-count=5
```

Do not rewrite public history after other contributors start depending on it
unless the repository owner explicitly asks for that.
