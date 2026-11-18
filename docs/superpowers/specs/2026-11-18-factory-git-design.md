# Factory-Git: PRD Branches, Task Worktrees, Subagent Review

Date: 2026-11-18
Status: approved in conversation; builder check resolved; awaiting plan

## Intent

Today every task commit lands directly on the workspace repo's checked-out
branch (usually `main`). There is no artifact to review, no way to deliver a
PRD as one reviewable change, and no independent check that a task actually met
its acceptance criteria before the loop moves on.

This design gives each PRD a branch, each task an isolated worktree cut from
that branch, and a researcher → coder → reviewer chain per task. Work stays
sequential: one task in flight at a time. The point is isolation, a clean diff
to review, and a PASS the host can verify — not concurrency.

## Goals

- One branch per PRD per touched workspace repo (`{type}/{slug}`), merged from
  the repo's base branch and left ready for a human to open a PR.
- Every task implemented in its own worktree on its own branch
  (`{type}/{slug}-TASK-{id}`), so a failed task cannot touch the operator's
  checkout or the PRD branch.
- A subagent chain per task with enforced roles: `researcher` (read-only recon),
  `coder` (implementation + verification), `reviewer` (independent verdict).
- A machine-readable verdict bound to the exact commits reviewed. No matching
  verdict, no merge, no task completion.
- `pi` support removed; `opencode` is the only agent.

## Non-goals

- Parallel task execution. Independent tasks still run one per iteration.
- Automatic conflict resolution. A merge conflict aborts the whole task.
- Creating GitHub repos. `finish` pushes and opens PRs only where a remote and
  `gh` already exist.
- Preserving `pi` as a degraded mode.
- Migrating PRD-001 / PRD-002 work into retroactive branches.
- A PRD index file. The PRD files themselves are the list; see Naming.
- Docker/compose-based tasks inside worktrees. The current compose file is
  untracked at the workspace root and belongs to the operator's checkouts.

## Anti-goals

- The reviewer becoming a rubber stamp over the coder's own reasoning.
- Agent-written state transitions. The host still owns `tasks.json`, the log,
  every merge, and every branch deletion.
- Worktree sprawl: a task that ends without completing must leave no branch,
  no worktree, and no manifest behind.
- A second copy of PRD metadata that can drift from the PRD file.

## Constraints

- Sequential loop: `ralph.sh` still spawns one agent process per iteration and
  keeps its checkpoint / circuit-breaker behavior.
- The agent process inherits `ralph.sh`'s cwd, which is the **repo root**
  (`ralph.sh` does `cd "$SCRIPT_DIR"` and `run_agent_command` never changes
  it). opencode therefore discovers `ralph-loop/opencode.jsonc` and
  `ralph-loop/.opencode/`. `.opencode` under `workspace/` is not discovered.
- `workspace/` may contain one repo or several. Branch model is per repo, and
  repos a PRD does not touch must stay untouched.
- opencode v2.2.7: agents come from `.opencode/agents/<name>.md` with
  `mode: subagent` and ordered `permissions` where the last match wins;
  `opencode debug agents` lists what resolved.
- `base_sha` merging requires the integration worktree to be the only writer
  of the PRD branch.

## Approaches considered

**A. One CLI run per task; lead agent + three subagents (chosen).** `ralph.sh`
spawns `opencode` once per task against a `factory-lead` primary agent. The lead
launches `researcher`, `coder`, `reviewer` as child sessions. Git verbs that
change branches are host-side shell commands. One process per iteration keeps
checkpointing, transcript parsing, and the circuit breaker intact.

**B. Three host-staged CLI runs per task.** Host runs research, then code, then
review as separate processes. Equally deterministic and the only option if the
agent lacks subagents. Rejected: three process startups per task (~6-9s each),
three contexts, and no follow-up between researcher and coder.

**C. Agent owns git.** Lead creates branches, worktrees, and merges, and emits
the promise when it decides it is done. Least host code. Rejected: PASS becomes
advisory, a failed iteration can leave a half-merged PRD branch, and it breaks
the invariant that the host owns state transitions.

## Decisions

- **PRD branch is lazy, per repo.** Created at the first task whose researcher
  reports that repo in `affected_repos`. A PRD that never touches a repo never
  branches it.
- **Branch names are semantic and derived from the PRD frontmatter**: the PRD
  file is the only source of truth for `slug` and `type`. There is no PRD
  registry and no index file.
- **Merging happens in a dedicated integration worktree**, not in
  `workspace/<repo>`. The operator's checkout stays on the base branch for the
  PRD's whole life, so rollback can never eat their work.
- **`--no-ff` per task**, so each merged task is one revertable commit.
- **Merge is all-or-nothing across repos.** A conflict in any repo resets every
  already-merged repo's PRD branch to its pre-merge SHA before failing.
- **Verdicts are files bound to SHAs**, not prose. The reviewer records the
  `base_sha` and `head_sha` of every repo it reviewed; `merge` refuses unless
  each SHA still matches.
- **`verify` is added to the task spec** as per-repo command lists. Coder runs
  it before committing; reviewer re-runs it before writing PASS.
- **Host-only verbs are gated by `RALPH_HOST=1`**, set by `ralph.sh` only on its
  own invocations. Same honesty model as the workspace rule, but explicit.
- **The agent's cwd stays the repo root.** Agent definitions live at
  `.opencode/agents/` and the per-run skills link is created at
  `.opencode/skills` (not under `workspace/`, where opencode never looks).

## Design

### PRD frontmatter and git naming

`PRD-{id}.md` frontmatter gains two fields:

```yaml
---
id: "PRD-002"
slug: "note-search"
type: "feat"          # feat | fix | refactor | chore | docs | test | perf
title: "Note Search"
created_at: "2026-11-18T10:00:00Z"
---
```

- `id` — stable key used by task specs and reports.
- `slug` — required for any PRD with runnable tasks,
  `^[a-z0-9]+(-[a-z0-9]+)*$`, max 40 chars, unique across PRDs.
- `type` — optional, defaults to `feat`.

| Artifact | Name |
|---|---|
| PRD branch | `feat/note-search` |
| Task branch | `feat/note-search-TASK-003` |
| Worktree | `workspace/.worktrees/note-search/TASK-003/<repo>` |
| PR title | `feat(note-search): Note Search` |

Task branches are siblings of the PRD branch because git cannot hold both
`refs/heads/feat/x` and `refs/heads/feat/x/TASK-1`: the first is a ref and the
second requires it to be a directory. Any nested form fails at
`git worktree add -b` with "cannot lock ref".

If `{type}/{slug}` already exists in a repo, `prepare` fails with a collision
error; a reused slug is a naming conflict, not a resume signal.

### Deriving the PRD list

`ralph.sh` and `factory-git.sh` read `.agent/prd/*.md` frontmatter directly:

- Which PRDs exist: the directory listing.
- Which are complete: every task whose spec `prd` resolves to that file has
  `status: "completed"`.
- Which repos a PRD touched: the manifests under
  `workspace/.worktrees/{slug}/`, or `git log base..branch` in the integration
  worktree.
- Whether the PR is merged: a human fact. `finish` prints the commands; the loop
  never needs to know.

Legacy PRDs without `slug`/`type` are tolerated as long as every task
referencing them is already `completed`. A runnable task pointing at a slugless
PRD fails with "PRD-002.md has no slug; add one before running its tasks".

### Branch and worktree layout

```
workspace/
├── simple-notes-api/                                   ← stays on main, untouched
└── .worktrees/
    └── note-search/
        ├── _integration/
        │   └── simple-notes-api/                       ← on feat/note-search
        └── TASK-001/
            ├── .manifest.json
            └── simple-notes-api/                       ← on feat/note-search-TASK-001
```

`prepare` adds `.worktrees/` to each source repo's `.git/info/exclude`
(idempotent, not tracked) and `find_workspace_git_repos` skips the directory.

Base branch resolution: `RALPH_BASE_BRANCH` env, then `main`, then `master`;
error if none. `prepare` refuses when a source repo is dirty.

### Manifest

`workspace/.worktrees/{slug}/TASK-{id}/.manifest.json`:

```json
{
  "task_id": "TASK-001",
  "prd": "PRD-002",
  "slug": "note-search",
  "type": "feat",
  "created_at": "2026-11-18T10:00:00Z",
  "repos": [
    {
      "name": "simple-notes-api",
      "source": "/abs/ops/workspace/simple-notes-api",
      "source_head": "9607772...",
      "integration_worktree": "/abs/ops/workspace/.worktrees/note-search/_integration/simple-notes-api",
      "worktree": "/abs/ops/workspace/.worktrees/note-search/TASK-001/simple-notes-api",
      "base_sha": "9607772...",
      "prd_branch": "feat/note-search",
      "task_branch": "feat/note-search-TASK-001",
      "base_branch": "main"
    }
  ]
}
```

`source_head` is the operator checkout's HEAD at prepare time. `merge` refuses
if it moved, which catches a coder that committed to `workspace/<repo>` instead
of its worktree. `base_sha` is the PRD branch tip at prepare time; reviewer
diffs `base_sha...HEAD` because `git status` is clean after the coder commits.

### Worktree hydration

Git does not carry `node_modules`, `.env`, or local databases into a worktree.
`prepare` does the minimum:

- symlink `node_modules` from the source checkout when it exists;
- copy `.env` and `.env.*` files (never symlink — the coder must not edit the
  operator's secrets);
- everything else is the task's job, stated in its steps.

Untracked files at the workspace root (`docker-compose.yml`) are not copied;
docker/e2e tasks in worktrees are out of scope for this version.

### `scripts/factory-git.sh`

| Verb | Actor | Behavior |
|---|---|---|
| `prepare TASK-{id} --repos a,b` | lead | Resolve PRD frontmatter from the task spec. Clear stale `TASK-{id}.review.json` and `TASK-{id}.md`. Create `{type}/{slug}` from the base branch in each repo if absent; create the integration and task worktrees; hydrate; write the manifest. Idempotent for an intact manifest; `abort` first if stale. |
| `status TASK-{id}` | either | Print a table: repo, task branch, base sha, dirty state, commits ahead. |
| `merge TASK-{id}` | host | Require a verdict whose `base_sha`/`head_sha` match every repo, and `source_head` unchanged. Record pre-merge PRD SHAs, then `git merge --no-ff --no-edit` per repo with commits. Any failure: `merge --abort` the current repo, `reset --hard` every already-merged repo to its recorded SHA, exit non-zero. Success: remove the worktree, delete the task branch, delete the verdict. |
| `abort TASK-{id}` | host | `git worktree remove --force`, `git branch -D`, delete manifest, task dir, verdict, and report. If a merge was interrupted, reset the PRD branch to the manifest's recorded pre-merge SHAs. Never removes the integration worktree. |
| `finish PRD-{id}` | host/human | Read frontmatter and touched repos. For each repo print `git push -u origin {branch}` and `gh pr create --base {base} --head {branch} --title "{type}({slug}): {title}" --body-file .agent/prd/PRD-{id}.md`; run only with `--push`; skip with a warning when a repo has no remote or `gh` is absent. |

`merge`, `abort`, and `finish` require `RALPH_HOST=1`. `prepare` and `status`
are agent-callable. Verbs return distinct non-zero codes so the host can tell
"conflict" from "missing verdict" from "source moved".

### Verdict

`.agent/reports/TASK-{id}.review.json`, written only by the reviewer:

```json
{
  "task_id": "TASK-001",
  "verdict": "PASS",
  "reviewed": [
    { "repo": "simple-notes-api", "base_sha": "9607772", "head_sha": "a1b2c3d" }
  ],
  "verify": [
    { "repo": "simple-notes-api", "commands": ["npm test"], "exit_code": 0 }
  ],
  "acceptance": [
    { "criterion": "GET /api/notes returns notes ordered by updated_at DESC",
      "evidence": "tests/notes.test.ts:42" }
  ],
  "defects": []
}
```

`merge` recomputes each worktree HEAD and rejects on any mismatch. A stale PASS
from a previous attempt cannot satisfy a new one.

### Task spec addition

`TASK-{id}.json` gains optional per-repo verification:

```json
"verify": [
  { "repo": "simple-notes-api", "commands": ["npm test", "npm run build"] },
  { "repo": "*", "commands": ["make lint"] }
]
```

Commands run with cwd = `{worktree}/{repo}`; `"repo": "*"` runs in every repo.
When absent, the coder derives the project's own commands per repo and the
reviewer records what it actually ran. Generation stays `status: "pending"`
only; `in_progress` remains runtime-only.

### Subagents

Canonical, tracked definitions in `.opencode/agents/` at the repo root — the
agent's cwd — so no per-run copy is needed. Project definitions merge over any
global agent of the same name; permissions append, last match wins.

| Agent | Mode | Permissions |
|---|---|---|
| `factory-lead` | primary | `edit` deny; `subagent` deny `*` then allow `researcher`, `coder`, `reviewer`; `shell` allow. Runs `prepare` and `status` only. |
| `researcher` | subagent | `edit` deny; `read`/`glob`/`grep` allow; `shell` allow for inspection. Returns `{affected_repos, target_files, reference_patterns, risks}`. |
| `coder` | subagent | `edit` allow; `shell` allow; `subagent` deny. Prompt-restricted to manifest worktree paths. TDD, runs `verify`, commits per repo. |
| `reviewer` | subagent | `edit` deny `*` then allow `.agent/reports/*`; `shell` allow for `git diff` and `verify`; `subagent` deny. Never sees the coder's reasoning. |

Preflight asserts the four IDs through `opencode debug agents` from the repo
root, and warns (does not fail) when a global agent shares a name.

### Lead workflow per task

1. Read the task spec, its PRD, and `STEERING.md`.
2. Launch `researcher` with the spec and PRD path; expect the JSON brief.
3. Run `factory-git.sh prepare TASK-{id} --repos <affected_repos>`; read the
   manifest.
4. Launch `coder` with the spec, manifest, and verify commands.
5. Launch `reviewer` with the spec, PRD, manifest, and the coder's report —
   never the coder's chat.
6. PASS → emit `<promise>TASK-{id}:DONE</promise>` and stop.
   FAIL → relaunch `coder` with the defect list (max 2 rounds), then re-review.
   Still FAIL → emit `<promise>BLOCKED:review failed</promise>` and stop.
7. Never merge. Never edit code. Never write `.agent/tasks.json`.

### Host flow after the agent exits

1. `TASK-{id}:DONE` → `factory-git.sh merge TASK-{id}`.
   - Success (including no-op) → `mark_task_complete`, log, commit orchestrator.
   - Any non-zero → `abort`, treat as a failed iteration, roll back the
     checkpoint, feed the circuit breaker.
2. `BLOCKED` / `DECIDE` / no promise / crash → `abort`, then the existing
   failure handling.
3. All tasks complete → for every PRD with all tasks completed and a branch,
   print `factory-git.sh finish PRD-{id}`.

### Failure, rollback, and the circuit breaker

Task work never exists outside a worktree, so failure cleanup is `abort` plus
checkpoint restore of the operator's checkouts. `checkpoint.sh` stays as the
safety net against an agent editing the main checkout directly, now ignoring
`.worktrees/`. PRD branches only move via a successful merge; a conflict resets
them to the recorded pre-merge SHA. Circuit-breaker semantics are unchanged.

### Removing `pi`

Delete: the `SUPPORTED_AGENTS` entry and every `pi` case in `agents.sh`
(`is_supported_agent`, `agent_display_name`, `agent_min_version`,
`prepare_pi_state`, `build_pi_command`), the pi branches in `preflight.sh`,
`MIN_PI_VERSION` in `constants.sh`, the pi JSONL paths in `output.sh`, pi lines
in `display.sh`, and every pi mention in README/AGENTS. `--agent` stays accepted
but only `opencode` is valid; anything else errors as an unknown agent.

`.pi/` stays on disk and stays gitignored. It may hold user credentials, and
deleting a user's local secrets is not part of removing an agent from the code.
Only code and documentation references to `pi` go away.

## Files

| File | Change |
|---|---|
| `scripts/factory-git.sh` | new: prepare / status / merge / abort / finish |
| `scripts/lib/factory.sh` | new: manifest read/write, PRD frontmatter parsing, slug validation, base-branch resolution, hydration, repo discovery |
| `scripts/lib/agents.sh` | drop pi, always `--agent factory-lead`, link skills at repo root |
| `scripts/lib/preflight.sh` | drop pi, assert the four agents resolve, assert `factory-git.sh` is present, warn when a pending task's PRD has no slug |
| `scripts/lib/output.sh` | keep opencode JSONL only |
| `scripts/lib/checkpoint.sh` | ignore `.worktrees/` |
| `scripts/lib/constants.sh` | drop `MIN_PI_VERSION`; add git exit codes |
| `ralph.sh` | merge/abort calls around the promise, finish on completion |
| `.opencode/agents/{factory-lead,researcher,coder,reviewer}.md` | new, tracked |
| `.agent/PROMPT.md` | rewritten as the factory-lead contract |
| `AGENTS.md`, `README.md` | branch model, worktrees, subagents, cwd, no pi |
| `.agents/skills/prd-creator/{SKILL,PRD,JSON}.md` | `slug`/`type` frontmatter, `verify` field |
| `.gitignore` | keep `.pi/` (local secrets); replace blanket `.opencode/` with `.opencode/skills` |

## Verification

- `bash -n ralph.sh`, every `scripts/lib/*.sh`, and `scripts/factory-git.sh`.
- Fixture test in `/tmp`: two throwaway repos; assert `prepare` branch names,
  worktree layout, manifest, hydration; `merge` `--no-ff` commit, no-op path,
  conflict path (non-zero, both PRD branches back at pre-merge SHA), verdict SHA
  mismatch rejection, source-repo-moved rejection; `abort` leaves no branch,
  worktree, verdict, or manifest; slug collision fails; `finish` prints per-repo
  commands and skips a repo without a remote.
- `opencode debug agents` from the repo root lists all four agents.
- One real `./ralph.sh --once` on a trivial task with `9Router/combo1` (slow,
  ~70s per trivial call): worktree created, coder commits there, verdict bound
  to HEAD, host merges into `feat/{slug}`, task marked complete, operator's
  checkout still on `main`, worktree removed.

## Left to the builder

- Exact non-zero exit-code numbers for the git verbs.
- Whether to warn or hard-fail when `node_modules` is absent in the source
  checkout at prepare time (recommend warn; the coder installs).
- `jq` shape for the manifest and verdict, beyond the fields named here.
