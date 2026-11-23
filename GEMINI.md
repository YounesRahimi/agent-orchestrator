# Fork Rules (`YounesRahimi/agent-orchestrator`)

This repository is a personal fork of `OrchestratorInc/agent-orchestrator`.

## Minimize Changes to Upstream-Owned Files

- **Keep changes to upstream-owned files as small as possible.** Every touched line in an upstream file increases rebase conflict surface when syncing `dev` onto `upstream/main`.
- **Prefer new fork-only files over editing upstream files:**
  - Put fork docs, rules, and build/sync scripts in standalone files (`GEMINI.md`, `FORK.md`, `scripts/install-local.sh`, `scripts/update-local.sh`).
  - Do not edit upstream `AGENTS.md`, `README.md`, `package.json`, or `Makefile` for fork-only workflow notes or helpers.
  - When adding fork-specific behavior to Go or TypeScript code, place the implementation in a separate `*_fork.go` / `*-fork.ts` overlay file and wire it into the upstream file with the smallest possible hook (1–3 lines where feasible).
- **Keep `main` clean:** Local `main` tracks `upstream/main` as an unmodified mirror. All fork commits live on `dev` (or short-lived topic branches branched from `dev`).
- **Sync via rebase:** Use `scripts/update-local.sh` to rebase `dev` onto `upstream/main`, drop fork commits that upstream supersedes, and reinstall locally.
