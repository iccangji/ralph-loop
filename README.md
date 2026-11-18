# Ralph Wiggum Loop

Ralph runs an AI coding agent CLI on the host in an autonomous loop. Every PRD
gets its own git branch, every task is implemented in an isolated worktree, and
a task only reaches the PRD branch after an independent reviewer returns PASS.

## Architecture

```
ralph.sh (host)
   │  selects one task, checkpoints, spawns opencode
   ▼
opencode --agent factory-lead
   ├── researcher   read-only recon: repos, files, patterns, risks
   ├── prepare      host-owned branches + worktrees (factory-git.sh)
   ├── coder        TDD inside the worktree, runs verify, commits once per repo
   └── reviewer     diffs base..HEAD, re-runs verify, writes a SHA-bound verdict
   │
   ▼  <promise>TASK-x:DONE</promise>
ralph.sh (host) merges --no-ff into the PRD branch, marks the task complete
```

- **Host**: owns `.agent/tasks.json`, `.agent/logs/LOG.md`, every merge, every
  branch deletion, and the checkpoint/rollback. Agents never touch them.
- **Factory lead**: a primary opencode agent. It delegates and stops; it cannot
  edit files or move branches.
- **Agents live in the repo root** (`.opencode/agents/`), which is the agent's
  working directory. Project skills are linked per run into `.opencode/skills`.
- **opencode is the only agent.** `--agent` still exists but only `opencode` is
  accepted.
- Model pins live in `opencode.jsonc` under `agents.<id>.model`. Agent markdown
  files define behavior and permissions only.

> **Boundary:** the workspace-only rule is enforced by opencode permission
> rules, not by a sandbox. Run Ralph on a host and account you control.

## Branch and worktree model

Names come from the PRD frontmatter, never from its title:

```yaml
---
id: "PRD-002"
slug: "note-search"
type: "feat"          # feat | fix | refactor | chore | docs | test | perf
title: "Note Search"
created_at: "2026-11-18T10:00:00Z"
---
```

| Artifact | Name |
|---|---|
| PRD branch (per repo) | `feat/note-search` |
| Task branch (per repo) | `feat/note-search-TASK-003` |
| Worktree | `workspace/.worktrees/note-search/TASK-003/<repo>` |

```
workspace/
├── simple-notes-api/                          ← stays on main, untouched
└── .worktrees/
    └── note-search/
        ├── _integration/simple-notes-api/     ← on feat/note-search
        └── TASK-003/simple-notes-api/         ← on feat/note-search-TASK-003
```

Task branches are siblings of the PRD branch because git cannot hold both
`feat/x` and `feat/x/TASK-1` as refs. The PRD branch is created lazily, at the
first task that touches a repo. `.worktrees/` is added to each repo's
`.git/info/exclude` so it never shows up as untracked.

`prepare` hydrates a worktree: `node_modules` is symlinked from the source
checkout, and `.env*` files are copied (never linked, so a task cannot rewrite
the operator's secrets). Docker/compose tasks inside worktrees are out of scope.

## Directory Layout

```
.
├── .agents/skills/         # Shared skills (source of truth)
├── .agent/
│   ├── PROMPT.md           # Factory-lead contract
│   ├── STEERING.md         # Critical steering instructions
│   ├── tasks.json          # Minimal queue (gitignored)
│   ├── tasks/              # Task specs TASK-{ID}.json
│   ├── prd/                # PRD-{ID}.md and SUMMARY.md
│   ├── reports/            # Reviewer verdicts (gitignored)
│   ├── logs/LOG.md         # Progress log (host-managed)
│   └── history/            # Raw iteration transcripts
├── .opencode/agents/       # factory-lead, researcher, coder, reviewer
├── opencode.jsonc          # Model pins and permission rules
├── workspace/              # Target project (gitignored)
└── scripts/
    ├── factory-git.sh      # prepare / status / merge / abort / finish
    └── lib/
```

## Requirements

- `bash`, `git`, `curl`, `jq`
- `opencode` >= 1.19.0 on `PATH`, with provider credentials in
  `~/.config/opencode/opencode.jsonc`
- Docker is **optional**. It is used only when the project has a compose file,
  to start and tear down the project's service stack.

## Quickstart

1. Set the provider and model for each agent in `opencode.jsonc`:

   ```jsonc
   "agents": {
     "factory-lead": { "model": "provider/model" },
     "researcher":  { "model": "provider/model" },
     "coder":       { "model": "provider/model" },
     "reviewer":    { "model": "provider/model" }
   }
   ```

2. Initialize the target project in `workspace/`. A single repo or one repo per
   service both work. Each source repo must be clean and have a `main` or
   `master` branch (or set `RALPH_BASE_BRANCH`).

3. Define tasks:

   ```bash
   cp .agent/tasks.json.example .agent/tasks.json
   ```

   Use the `prd-creator` skill to write `.agent/prd/PRD-{ID}.md` (with `slug`)
   and the matching task specs.

4. Run Ralph:

   ```bash
   ./ralph.sh --once
   ./ralph.sh
   ```

## Task spec

```json
{
  "id": "TASK-003",
  "title": "Add note search endpoint",
  "category": "feature",
  "prd": ".agent/prd/PRD-002.md",
  "description": "…",
  "depends_on": ["TASK-002"],
  "steps": ["…", "…"],
  "acceptance_criteria": ["…", "…"],
  "verify": [
    { "repo": "simple-notes-api", "commands": ["npm test", "npm run build"] }
  ]
}
```

`verify` is per repo; `"repo": "*"` runs everywhere. Commands run with the task
worktree as cwd. When absent, the coder derives the project's commands.

## Options

- `--once`: Run a single iteration and stop.
- `--agent AGENT`, `-a AGENT`: Only `opencode` is valid.
- `--max-iterations N`: Maximum iterations before stopping (default: 10).
- `--max-retries N`: Consecutive failed iterations before the circuit breaker
  trips (default: 3, 0 to disable).
- `--no-rollback`: Keep workspace state on failure for debugging.
- `--help`: Display usage and options.
- `-- ARGS...`: Extra arguments forwarded to the agent CLI.

## Safety Features

### Isolation and rollback

Task work only ever exists inside `workspace/.worktrees/`. On failure the host
runs `factory-git.sh abort`, which removes the worktree, deletes the task
branch, and deletes the verdict. It never moves the PRD branch. The operator's
checkout stays on its base branch for the PRD's entire life, so a rollback
cannot eat your work.

`checkpoint.sh` still snapshots the source repos each iteration and ignores
`.worktrees/`. A coder that edits `workspace/<repo>` directly is caught: the
manifest records the checkout's HEAD at prepare, and `merge` refuses if it moved.

At startup Ralph discards every orphaned manifest left by a crashed run and runs
`git worktree prune`, so a hard kill cannot block the next run.

### Verdict gate

The reviewer writes `.agent/reports/TASK-{id}.review.json`:

```json
{
  "task_id": "TASK-003",
  "verdict": "PASS",
  "reviewed": [
    {"repo": "simple-notes-api", "base_sha": "9607772", "head_sha": "a1b2c3d"}
  ],
  "verify": [{"repo": "simple-notes-api", "commands": ["npm test"], "exit_code": 0}],
  "acceptance": [{"criterion": "…", "evidence": "tests/notes.test.ts:42"}],
  "defects": []
}
```

`merge` recomputes each worktree HEAD and refuses on any mismatch, so a PASS
from an earlier attempt cannot satisfy a later one. Merge is all-or-nothing
across repos: a conflict in one repo resets every already-merged repo to its
pre-merge SHA.

`prepare` clears stale verdicts. `merge`, `abort`, and `finish --push` require
`RALPH_HOST=1`, which `ralph.sh` sets only for its own calls. The agent
permissions also deny `factory-git.sh merge|abort|finish` and `RALPH_HOST=*`, so
a hallucinated call is refused by the tool layer too. This is a cooperation
boundary, not a sandbox: a shell a user hands an agent is still a shell.

### Circuit breaker

After `MAX_RETRIES` consecutive iterations without a completed task, Ralph exits
with code 7. Tasks already merged into the PRD branch stay there; a failed
iteration never resets a PRD branch.

## Publishing a PRD

When the queue drains, Ralph prints (but does not run) the push and PR commands
for each completed PRD. To publish:

```bash
RALPH_HOST=1 ./scripts/factory-git.sh finish PRD-002 --push
```

`finish` warns when the base branch has moved and prints the rebase command; it
never rebases for you. Repos without an `origin` remote or without `gh` are
skipped with a warning.

## Development

```bash
bash -n ralph.sh
for f in scripts/lib/*.sh scripts/factory-git.sh; do bash -n "$f"; done
bash scripts/tests/factory-git-test.sh
```

## Reuse as a template

Per-session artifacts are gitignored: `workspace/`, `.agent/prd/`,
`.agent/tasks/`, `.agent/tasks.json`, `.agent/reports/`, `.agent/history/`,
`.agent/logs/LOG.md`, and `.opencode/skills`. Clone the repo, copy
`.agent/tasks.json.example`, write a PRD, and run.
