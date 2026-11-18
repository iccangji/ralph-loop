---
name: ralph-runner
description: Use when you need to execute the full Ralph pipeline: run ralph.sh iterations, monitor task completion, and publish PRs via factory-git.sh finish. Covers required environment, command sequence, common flags, and troubleshooting.
---

# Ralph Pipeline Runner

Execute the complete Ralph autonomous loop from PRD → tasks → implementation → PR.

## Quick Reference

| Goal | Command |
|------|---------|
| Single iteration (smoke test) | `./ralph.sh --once` |
| Full autonomous run | `./ralph.sh` |
| Max N iterations | `./ralph.sh --max-iterations N` |
| Publish finished PRD (Bitbucket) | `BITBUCKET_API_TOKEN=xxx RALPH_HOST=1 ./scripts/factory-git.sh finish PRD-001 --push` |
| Publish finished PRD (GitHub) | `RALPH_HOST=1 ./scripts/factory-git.sh finish PRD-001 --push` |
| Check task status | `./scripts/factory-git.sh status TASK-003` |
| Abort a stuck task | `RALPH_HOST=1 ./scripts/factory-git.sh abort TASK-003` |

---

## Prerequisites Checklist

Before running, verify:

- [ ] `opencode` CLI installed and on PATH (`opencode --version` ≥ 1.19.0)
- [ ] `jq`, `git`, `curl` available
- [ ] `opencode.jsonc` has model pins for `factory-lead`, `researcher`, `coder`, `reviewer`
- [ ] `.agent/prd/PRD-{ID}.md` exists with `slug` and `type` frontmatter
- [ ] `.agent/tasks.json` populated (copy from `.agent/tasks.json.example`)
- [ ] `.agent/tasks/TASK-{ID}.json` specs exist with `verify` commands
- [ ] `workspace/` has clean git repos on `main`/`master` (or set `RALPH_BASE_BRANCH`)
- [ ] For Bitbucket PR: `BITBUCKET_API_TOKEN` exported in your shell
- [ ] For GitHub PR: `gh` CLI authenticated (`gh auth status`)

---

## Execution Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. PREPARE                                                       │
│    cp .agent/tasks.json.example .agent/tasks.json               │
│    # Use prd-creator skill to generate PRD + tasks              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. SMOKE TEST (optional but recommended)                        │
│    ./ralph.sh --once                                            │
│    # Verifies: worktree created, coder commits, reviewer PASS,  │
│    # host merges, task marked complete, operator checkout clean │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. FULL RUN                                                      │
│    ./ralph.sh                                                   │
│    # Runs until all tasks completed or circuit breaker trips    │
│    # Exit codes: 0=done, 1=max iter, 2=blocked, 3=decide, 7=breaker │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. PUBLISH (when queue drains, Ralph prints commands)           │
│    # For Bitbucket:                                             │
│    export BITBUCKET_API_TOKEN="your-token"                      │
│    RALPH_HOST=1 ./scripts/factory-git.sh finish PRD-001 --push  │
│    # For GitHub:                                                │
│    RALPH_HOST=1 ./scripts/factory-git.sh finish PRD-001 --push  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Required Environment Variables

| Variable | Who Sets It | Purpose |
|----------|-------------|---------|
| `RALPH_HOST=1` | **Host only** (`ralph.sh` sets it internally) | Gates `merge`, `abort`, `finish --push`. **Never export manually** — it bypasses the agent guard. |
| `BITBUCKET_API_TOKEN` | **You (human)** | Bitbucket REST API auth for PR creation. Export in shell before `finish --push`. |
| `GITHUB_TOKEN` / `GH_TOKEN` | **You (human)** | Used by `gh` CLI automatically for GitHub PR creation. |

---

## Common Flags

```bash
./ralph.sh --once                    # One iteration, then stop
./ralph.sh --max-iterations 20       # Override default 10
./ralph.sh --max-retries 5           # Override default 3 (circuit breaker)
./ralph.sh --no-rollback             # Keep workspace state on failure (debug)
./ralph.sh --agent opencode          # Explicit (only valid value)
./ralph.sh -- --model combo1         # Extra args forwarded to opencode
```

---

## Monitoring & Debugging

| Need | Command |
|------|---------|
| Watch live progress | `tail -f .agent/logs/LOG.md` |
| Raw agent transcript | `cat .agent/history/TASK-003.md` |
| Task queue status | `jq '.[] | "\(.id) \(.status) p=\(.priority)"' .agent/tasks.json` |
| Worktree layout | `find workspace/.worktrees -maxdepth 3 -type d` |
| Verdict file | `cat .agent/reports/TASK-003.review.json` |
| PRD branch status | `git -C workspace/simple-notes-api branch -a` |

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `opencode debug config` fails | Config not loaded | Ensure `opencode.jsonc` at repo root, not in workspace/ |
| "Missing agent definition" | Agents not in `.opencode/agents/` | Check `.opencode/agents/{factory-lead,researcher,coder,reviewer}.md` exist |
| "PRD has no valid slug" | Frontmatter missing `slug` | Add `slug: kebab-case-name` to PRD frontmatter |
| "Verdict does not match commits" | Stale verdict or worktree modified | `factory-git.sh abort TASK-XXX` then re-run |
| "Source checkout moved" | You edited `workspace/repo` directly | Only edit inside worktrees; `git -C workspace/repo checkout main` |
| "Cannot reach provider" | API endpoint down | Check `opencode.jsonc` provider `baseURL`; verify network |
| Circuit breaker (exit 7) | 3+ failed iterations | Check `.agent/logs/LOG.md`; fix root cause; re-run |
| Bitbucket PR not created | `BITBUCKET_API_TOKEN` not set | `export BITBUCKET_API_TOKEN=...` before `finish --push` |
| Multi-PRD warning | Pending tasks span >1 PRD | Expected; branches interleave. Monitor carefully. |

---

## Example: Full Session

```bash
# 0. Setup (once per project)
cd my-ralph-project
cp .agent/tasks.json.example .agent/tasks.json

# 1. Generate PRD + tasks (using prd-creator skill)
# ... grilling session produces .agent/prd/PRD-001.md with slug "user-auth"
# ... and .agent/tasks/TASK-001.json through TASK-005.json

# 2. Smoke test
./ralph.sh --once
# → Verifies pipeline works end-to-end

# 3. Full run
./ralph.sh
# → Runs iterations until all tasks complete
# → Prints finish commands when queue drains:
#    PRD branches are ready to publish:
#      git -C 'workspace/simple-notes-api' push -u origin 'feat/user-auth'
#      gh -R 'git@github.com:org/repo.git' pr create --base main --head feat/user-auth ...

# 4. Publish (Bitbucket example)
export BITBUCKET_API_TOKEN="atlassian-api-token"
RALPH_HOST=1 ./scripts/factory-git.sh finish PRD-001 --push
# → Pushes branch, creates PR via Bitbucket REST API

# 5. Verify
git -C workspace/simple-notes-api log --oneline feat/user-auth -3
```

---

## Key Concepts (Mental Model)

| Concept | What It Means |
|---------|---------------|
| **PRD branch** | `feat/{slug}` — one per PRD per repo, lives until `finish` |
| **Task branch** | `feat/{slug}-TASK-{id}` — one per task per repo, deleted after merge/abort |
| **Worktree** | `workspace/.worktrees/{slug}/TASK-{id}/{repo}` — isolated checkout for coder |
| **Integration worktree** | `workspace/.worktrees/{slug}/_integration/{repo}` — holds the PRD branch |
| **Verdict** | `.agent/reports/TASK-{id}.review.json` — SHA-bound PASS/FAIL from reviewer |
| **Host-only verbs** | `merge`, `abort`, `finish --push` — require `RALPH_HOST=1`, denied to agents |

---

## What NOT To Do

| Don't | Why |
|-------|-----|
| `export RALPH_HOST=1` in your shell | Bypasses agent guard; agent could merge its own work |
| Edit files in `workspace/repo/` directly | Operator checkout must stay on base branch; worktrees are for coding |
| Run `git push` inside a task worktree | Host owns publishing via `finish --push` |
| Skip the smoke test | First-run issues (missing slug, wrong model pin) waste full-run time |
| Delete `.agent/reports/TASK-*.review.json` | Verdict is evidence for merge; `prepare` cleans stale ones automatically |

---

## Integration with prd-creator

The `prd-creator` skill generates the inputs this pipeline consumes:

```
prd-creator (grilling) → PRD-001.md (with slug/type) + tasks.json + TASK-*.json
                                                       │
                                                       ▼
                                              ralph-runner executes
                                                       │
                                                       ▼
                                              factory-git.sh finish --push
```

Use them in sequence: grilling → ralph-runner → finish.