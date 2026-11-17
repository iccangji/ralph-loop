# Ralph Loop

Autonomous agent loop. `ralph.sh` runs an agent CLI (`opencode` by default, `pi` as an alternative) on the host against `workspace/`, one task per iteration, until every entry in `.agent/tasks.json` has `status: "completed"`.

## Managing Orchestrator Role

The host agent acts strictly as a **Manager and Orchestrator**:
- **Task Management Only**: Plan, define, refine, and validate `.agent/tasks.json`, `.agent/tasks/TASK-*.json`, and `.agent/prd/`.
- **No autonomous execution**: Never run `./ralph.sh` unless explicitly ordered by the user.
- **No direct workspace edits**: Implementation belongs entirely to the worker CLI in `workspace/`.
- **Priority**: Inspect `.agent/tasks.json` and task specs before answering questions or planning.

## Task Structure & Hierarchy (1:1:N)

```
[Grilling Session]
       │
       ▼ (1:1)
[.agent/prd/PRD-{ID}.md]      <-- Frontmatter: id, title, created_at
       │
       ▼ (1:N)
[.agent/tasks/TASK-{ID}.json] <-- Spec with "prd": ".agent/prd/PRD-{ID}.md"
       │
       ▼ (Index)
[.agent/tasks.json]           <-- Minimal queue (id, title, status, priority, depends_on)
```

### 1. Task Index: `.agent/tasks.json`
Minimal execution queue. No PRD links here.

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
- `status`: `"pending"` initially. Orchestrator sets `"completed"` on `<promise>TASK-x:DONE</promise>`. Transiently `"in_progress"`.
- `depends_on`: Required array of task IDs that must be `"completed"` before this task is runnable.

### 2. Task Spec: `.agent/tasks/TASK-{ID}.json`
Complete execution instructions for one task.

```json
{
  "id": "TASK-001",
  "title": "Scaffold project",
  "category": "setup",
  "prd": ".agent/prd/PRD-001.md",
  "description": "Full description of task.",
  "depends_on": [],
  "steps": [
    "Step 1 with exact commands/files",
    "Step 2 verification"
  ],
  "acceptance_criteria": [
    "Verifiable assertion"
  ]
}
```
- `prd`: Relative file path to owning PRD document (e.g. `.agent/prd/PRD-001.md`).

### 3. PRD Files: `.agent/prd/PRD-{ID}.md`
Multiple PRDs can coexist across sessions. Required YAML frontmatter:

```markdown
---
id: "PRD-001"
title: "Feature Title"
created_at: "2026-11-17T14:30:00Z"
---

# Feature Title
...
```

## Task Selection & Execution Rules

1. **Deterministic Selection** (`scripts/lib/selector.sh`):
   - Filters `status == "pending"`
   - All `depends_on` must have `status == "completed"`
   - Lowest `priority` number first (array order breaks ties)
   - Validates DAG (no cycles, no missing refs)
2. **Execution**: Worker CLI receives task spec in prompt, works in `workspace/`, commits git changes, and outputs `<promise>TASK-{ID}:DONE</promise>`.
3. **State Update**: Host orchestrator marks `status: "completed"`, appends `.agent/logs/LOG.md`, and commits orchestrator repo.

## Invariants & Guardrails

- **Host execution**: Workers run directly on the host (no container/sandbox runtime).
- **Workspace writes only**: Worker edits remain inside `workspace/`. Host owns `.agent/`.
- **Git Checkpoint & Rollback**: Each iteration checkpoints `workspace/`. Silent failures roll back automatically unless `--no-rollback` is given.
- **Circuit Breaker**: Exits with code 7 after `MAX_RETRIES` (default 3) consecutive silent failures.
- **Exit codes**: `0` = Complete, `1` = Max iterations, `2` = Blocked, `3` = Decide, `7` = Circuit breaker.

## Verification

```bash
bash -n ralph.sh && for f in scripts/lib/*.sh; do bash -n "$f"; done
```
Test selector/tasks logic against temporary fixtures in `/tmp`.

## Standards Summary

- **Simplicity First**: Minimum code that solves the problem. No speculative abstractions.
- **Surgical Edits**: Touch only what is required for the task.
- **Verification**: If unverified by tests or commands, it is not complete.
- **Conventional Commits**: `feat:`, `fix:`, `chore:`.
