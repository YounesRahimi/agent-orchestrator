# Local Fork Workflow

This fork (`YounesRahimi/agent-orchestrator`) tracks `OrchestratorInc/agent-orchestrator` (`upstream/main`) while keeping fork-specific fixes and tooling on `dev`.

## Policy

- Minimize edits to upstream-owned files (see [GEMINI.md](GEMINI.md)).
- Keep `main` as a clean mirror of `upstream/main`; do all fork work on `dev`.

## Prerequisites

- Go (matching `backend/go.mod`)
- Node.js & npm
- `git`

## Local Build & Install (`scripts/install-local.sh`)

```sh
scripts/install-local.sh                       # packaged app + ao CLI (default, no sudo)
scripts/install-local.sh --mode dev            # source-linked electron-forge launcher + ao
scripts/install-local.sh --mode daemon         # Go ao binary only (fast rebuild)
scripts/install-local.sh --mode deb            # build + install Linux .deb via sudo dpkg -i
```

| Flag | Effect |
| --- | --- |
| `--mode package\|dev\|daemon\|deb` | Install mode (`package` is the default). |
| `--prefix DIR` | Bin directory for `ao` and `agent-orchestrator` (default: `~/.local/bin`). |
| `--app-dir DIR` | Package mode bundle location (default: `~/.local/share/agent-orchestrator`). |
| `--skip-deps` | Skip `npm ci` / dependency install. |
| `--skip-prepare` | Skip `prepackage` / `premake` / `dev-prepare` asset builds. |
| `--update-desktop` | Update `~/.local/share/applications/agent-orchestrator.desktop`. |
| `--no-dpkg` | In `deb` mode, build the `.deb` without running `sudo dpkg -i`. |

## Sync & Update (`scripts/update-local.sh`)

```sh
scripts/update-local.sh                        # sync upstream/main, rebase dev, push, install (package)
scripts/update-local.sh --no-install           # sync + rebase + push only
scripts/update-local.sh --no-push --no-install # local dry-run rebase onto upstream/main
scripts/update-local.sh dev -- --mode daemon   # sync + rebuild Go daemon only
scripts/update-local.sh --resolve-ai           # ask omp to resolve rebase conflicts
```

| Flag | Effect |
| --- | --- |
| `--allow-dirty` | Proceed with uncommitted changes in the working tree. |
| `--no-sync` | Skip upstream fetch/rebase; pull from `origin` only. |
| `--no-push` | Rebase locally without pushing to `origin`. |
| `--no-install` | Skip running `scripts/install-local.sh`. |
| `--force-reset` | After pushing `dev`, reset `origin/main` to match `upstream/main`. |
| `--resolve-ai` | On rebase conflict, invoke `omp --auto-approve -p` (or `$AO_RESOLVE_BIN`). |
| `-- ARGS...` | Forward extra arguments to `scripts/install-local.sh`. |
