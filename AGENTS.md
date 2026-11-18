# Ralph Loop

Autonomous agent loop. `ralph.sh` runs `opencode` on the host, one task per
iteration, until every entry in `.agent/tasks.json` has `status: "completed"`.

Each PRD owns a git branch, each task is implemented in its own worktree, and a
task only reaches the PRD branch after an independent reviewer writes a PASS
verdict bound to the reviewed commits.

## Managing Orchestrator Role

The host agent acts strictly as a **Manager and Orchestrator**:

- **Task management only**: plan, define, refine, and validate
  `.agent/tasks.json`, `.agent/tasks/TASK-*.json`, and `.agent/prd/`.
- **No autonomous execution**: never run `./ralph.sh` unless explicitly ordered
  by the user.
- **No direct workspace edits**: implementation belongs to the coder subagent
  inside a task worktree. Never edit `workspace/<repo>` yourself.
- **Priority**: inspect `.agent/tasks.json` and the task specs before answering
  questions or planning.

## Pipeline

```
ralph.sh (host)
   │  select task → checkpoint → opencode --agent factory-lead
   ▼
factory-lead          delegates only; cannot edit files or move branches
   ├── researcher     read-only recon: repos, files, patterns, risks, verify cmds
   ├── factory-git.sh prepare   (host-owned branches + worktrees)
   ├── coder          TDD in the worktree, runs verify, one commit per repo
   └── reviewer       diff base..HEAD, re-runs verify, writes the verdict file
   │
   ▼  <promise>TASK-x:DONE</promise>
ralph.sh (host)       merge --no-ff into the PRD branch, mark complete, clean up
```

Agent definitions live in `.opencode/agents/` at the repo root, which is the
agent's working directory. Model pins live in `opencode.jsonc` under
`agents.<id>.model`; the Markdown files define behavior and permissions only.
`opencode` is the only supported agent — `--agent` is accepted but only
`opencode` is valid.

## Task Structure & Hierarchy (1:1:N)

```
[Grilling Session]
       │
       ▼ (1:1)
[.agent/prd/PRD-{ID}.md]      <-- Frontmatter: id, slug, type, title, created_at
       │
       ▼ (1:N)
[.agent/tasks/TASK-{ID}.json] <-- Spec with "prd": ".agent/prd/PRD-{ID}.md"
       │
       ▼ (Index)
[.agent/tasks.json]           <-- Minimal queue (id, title, status, priority, depends_on)
```

### 1. PRD: `.agent/prd/PRD-{ID}.md`

Multiple PRDs may coexist. Required frontmatter:

```yaml
---
id: "PRD-001"
slug: "note-search"
type: "feat"
title: "Note Search"
created_at: "2026-11-17T14:30:00Z"
---
```

- `slug`: required, kebab-case, unique, ≤ 40 chars. It names git branches, so
  it must not change after the first task runs.
- `type`: optional, defaults to `feat`. One of `feat`, `fix`, `refactor`,
  `chore`, `docs`, `test`, `perf`.

There is no PRD registry file. The PRD list is derived from
`.agent/prd/*.md` frontmatter plus the specs that reference them.

### 2. Task Index: `.agent/tasks.json`

Minimal execution queue, gitignored. Start from the template:

```bash
cp .agent/tasks.json.example .agent/tasks.json
```

```json
[
  {
    "id": "TASK-001",
    "title": "Scaffold project",
    "category": "setup",
    "specFilePath": ".agent/tasks/TASK-001.json",
    "priority": 1,
    "depends_on": [],
    "status": "pending"
  }
]
```

- `status`: `"pending"` initially, `"in_progress"` while a task runs,
  `"completed"` only after the review verdict passes **and** the task branch
  merges.
- `priority`: lower runs first; array order breaks ties.
- `depends_on`: task IDs that must be `"completed"` before this task is
  runnable.

Pending tasks may span several PRDs. Ralph allows that but logs a warning,
because more than one PRD branch will then be in flight.

### 3. Task Spec: `.agent/tasks/TASK-{ID}.json`

```json
{
  "id": "TASK-001",
  "title": "Scaffold project",
  "category": "setup",
  "prd": ".agent/prd/PRD-001.md",
  "description": "Full description of task.",
  "depends_on": [],
  "steps": ["Step 1 with exact commands/files", "Step 2 verification"],
  "acceptance_criteria": ["Verifiable assertion"],
  "verify": [
    { "repo": "simple-notes-api", "commands": ["npm test", "npm run build"] }
  ]
}
```

- `prd`: relative path to the owning PRD. Required for every runnable task.
- `verify`: per-repo commands. `"repo": "*"` runs them in every affected repo.
  Commands run with the task worktree as cwd, never the operator's checkout.
  The coder runs them before committing; the reviewer re-runs them before PASS.
  Omit it when the project has no useful check.

## Branch and Worktree Model

| Artifact | Name |
|---|---|
| PRD branch (per repo) | `{type}/{slug}` |
| Task branch (per repo) | `{type}/{slug}-TASK-{id}` |
| Worktree | `workspace/.worktrees/{slug}/TASK-{id}/{repo}` |
| Integration worktree | `workspace/.worktrees/{slug}/_integration/{repo}` |

Task branches are siblings, not children, of the PRD branch: git cannot hold
both `refs/heads/feat/x` and `refs/heads/feat/x/TASK-1`.

```
workspace/
├── simple-notes-api/                       ← stays on main, never moved
└── .worktrees/
    └── note-search/
        ├── _integration/simple-notes-api/  ← on feat/note-search
        └── TASK-003/simple-notes-api/      ← on feat/note-search-TASK-003
```

The PRD branch is created lazily at the first task that touches a repo.
`.worktrees/` is added to each repo's `.git/info/exclude`.

## Task Selection & Execution Rules

1. **Deterministic selection** (`scripts/lib/selector.sh`): filters
   `status == "pending"`, requires every `depends_on` to be `"completed"`,
   sorts by `priority` ascending with array order as tiebreak, and validates the
   DAG (no cycles, no missing refs).
2. **Prepare** (`factory-git.sh prepare`): the factory lead asks the researcher
   which repos the task touches, then the host-owned script creates the PRD
   branch, integration worktree, and per-repo task worktrees. It symlinks
   `node_modules` and copies `.env*` into each worktree.
3. **Implement**: the coder works only inside those worktrees, writes tests,
   runs `verify`, and makes one commit per repo per task.
4. **Review**: the reviewer diffs `base_sha..HEAD` per repo, checks each
   acceptance criterion, re-runs `verify`, and writes
   `.agent/reports/TASK-{id}.review.json`. FAIL returns the defect list to the
   coder; after two failed rounds the lead emits `BLOCKED`.
5. **Merge**: the host runs `factory-git.sh merge`, which re-checks every
   worktree HEAD against the verdict, merges `--no-ff` into the PRD branch, and
   only then marks the task `"completed"`.

## Invariants & Guardrails

- **The operator checkout never moves.** `workspace/<repo>` stays on its base
  branch for the PRD's entire life. The manifest records its HEAD at prepare;
  `merge` refuses if that HEAD moved or the checkout is dirty.
- **Verdicts are SHA-bound.** A verdict lists `base_sha` and `head_sha` for every
  repo in the manifest. `merge` recomputes HEAD and rejects any mismatch, so a
  PASS from an earlier attempt cannot satisfy a later one. `prepare` deletes
  stale verdicts.
- **Merges are all-or-nothing.** A conflict in one repo resets every
  already-merged repo to its pre-merge SHA.
- **Host-only verbs.** `merge`, `abort`, and `finish --push` require
  `RALPH_HOST=1`, which `ralph.sh` sets only for its own calls. Agent
  permissions also deny those `factory-git.sh` verbs and `RALPH_HOST=*`. This is
  a cooperation boundary, not a sandbox.
- **Abort on failure.** A provider error, `BLOCKED`, `DECIDE`, a failed review,
  or a failed merge runs `factory-git.sh abort`, which removes the worktree,
  deletes the task branch, and deletes the verdict. It never touches the PRD
  branch.
- **Crash recovery.** At startup Ralph discards orphaned manifests from a
  previous run and runs `git worktree prune`.
- **Circuit breaker.** Exits with code 7 after `MAX_RETRIES` (default 3)
  consecutive failed iterations. Tasks already merged stay on the PRD branch.
- **Host execution.** Agents run directly on the host as your user. Edits are
  limited to `workspace/` by opencode permission rules, not by a sandbox.
- **Exit codes**: `0` complete, `1` max iterations, `2` blocked, `3` decide,
  `4` runtime error, `5` auth error, `6` provider error, `7` circuit breaker,
  `10`–`18` git/factory errors (usage, conflict, no verdict, stale verdict,
  source moved, slug missing, slug collision, dirty source, bad manifest).

## Publishing a PRD

When the queue drains, Ralph prints the push and PR commands for each finished
PRD but does not run them:

```bash
RALPH_HOST=1 ./scripts/factory-git.sh finish PRD-002 --push
```

To publish automatically without manual step, run Ralph with `--publish`:

```bash
# Bitbucket
BITBUCKET_API_TOKEN=xxx ./ralph.sh --publish

# GitHub (needs gh auth)
./ralph.sh --publish
```

`finish` warns when the base branch has moved and prints the rebase command; it
never rebases for you.

## Verification

```bash
bash -n ralph.sh
for f in scripts/lib/*.sh scripts/factory-git.sh; do bash -n "$f"; done
bash scripts/tests/factory-git-test.sh
```

The fixture test runs against throwaway repos in a temp directory. Never point
tests at the real `workspace/`.

## Getting Started / Reuse Across Projects

1. **Initialize the queue**:
   ```bash
   cp .agent/tasks.json.example .agent/tasks.json
   ```
2. **Pin models** in `opencode.jsonc` under `agents.<id>.model` for
   `factory-lead`, `researcher`, `coder`, and `reviewer`.
3. **Generate the PRD and tasks**: use the `prd-creator` skill (via grilling) to
   write `.agent/prd/PRD-001.md` with a `slug` and populate
   `.agent/tasks.json` and `.agent/tasks/TASK-*.json`.
4. **Run** `./ralph.sh` when ready.

Per-session artifacts stay local and gitignored: `workspace/`, `.agent/prd/`,
`.agent/tasks/`, `.agent/tasks.json`, `.agent/reports/`, `.agent/history/`,
`.agent/logs/LOG.md`, `.opencode/skills`, and `.pi/`.

## Standards Summary

- **Simplicity First**: minimum code that solves the problem, no speculative
  abstractions.
- **Surgical Edits**: touch only what the task requires.
- **Verification**: if it is not verified by a test or command, it is not done.
- **Conventional Commits**: `feat:`, `fix:`, `chore:`.
