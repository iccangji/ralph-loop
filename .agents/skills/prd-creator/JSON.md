# Implementation Task Generation

Transform the completed PRD into simple, concise, actionable and verifiable implementation tasks in JSON format. This creates a comprehensive task list for developers (human or AI) to build and verify the product.

## When to Use

After completing PRD creation, ask the user:
"Your PRD is complete. Would you like me to generate implementation tasks? I'll create a comprehensive JSON task list that breaks down all features into verifiable development work."

Only proceed after user confirmation.

## Task Generation Workflow

You should read the PRD markdown file located in `PROJECT_ROOT/.agent/prd/PRD-{ID}.md`.
Each task in the PRD will have a unique ID, formatted as `TASK-${ID}`.
Use those IDs to generate the task list. If the PRD has a `Prerequisites and Access` section, `TASK-1` is reserved for prerequisite verification. If no prerequisites section exists, skip `TASK-1` and start with feature tasks.

Copy and track progress:

```
Task Generation Progress:
- [ ] Analyze the complete PRD-{ID}.md
- [ ] Generate prerequisite verification task (optional, only if PRD has prerequisites)
- [ ] Generate task index in `PROJECT_ROOT/.agent/tasks.json` (minimal, no prd field)
- [ ] Generate detailed spec for each task in `PROJECT_ROOT/.agent/tasks/TASK-${ID}.json` (with prd field pointing to .agent/prd/PRD-{ID}.md)
- [ ] Fill `verify` for every task that changes code
- [ ] Present complete task list to user for review
```

**CRITICAL**: If any of the tasks is unclear, invoke the **grilling** skill to interview the user about the ambiguous decisions.
If a question can be answered by exploring the codebase, explore the codebase instead.

## Optional First Task: Prerequisite Verification

If the PRD contains a `Prerequisites and Access` section, generate `TASK-1: Verify project prerequisites and access`.
If the PRD has NO prerequisites section, skip this task entirely and start directly with `TASK-2` (or the first feature task).

When included, `TASK-1` confirms:
- `PROJECT_ROOT/.env.local` exists and contains placeholder entries for every required environment variable name from the PRD
- The user has manually filled real local values where needed, without copying those values into the PRD, task specs, logs, or chat
- Database access can be verified or the missing access is explicitly recorded
- Required MCP servers/tools are available and authenticated, or gaps are explicitly recorded
- Required service documentation links are available and relevant
- Required login/test users exist or there are clear steps to create/request them
- Any open prerequisite gaps have a user-approved proceed/block decision from the PRD

All downstream implementation tasks that require these prerequisites must include `TASK-1` in `depends_on`.

Use this shape for the prerequisite task:

```json:PROJECT_ROOT/.agent/tasks/TASK-1.json
{
  "id": "TASK-1",
  "title": "Verify project prerequisites and access",
  "category": "setup",
  "prd": ".agent/prd/PRD-001.md",
  "description": "Verify that required database access, MCPs, service documentation, environment variables, and login/test users are available before implementation begins.",
  "acceptance_criteria": [
    "`PROJECT_ROOT/.env.local` exists with placeholder entries for every required environment variable name listed in the PRD",
    "Real secret values are not written to the PRD, task specs, repository, logs, or chat",
    "The user has manually filled required local secret values in `.env.local` where needed",
    "Database connectivity is verified, or the missing access is recorded with a user-approved proceed/block decision",
    "Required MCP servers/tools are installed and authenticated, or gaps are recorded with a user-approved proceed/block decision",
    "Required service documentation links are available to the implementer",
    "Required login/test users are available or documented with request/create steps, without passwords or secret values"
  ],
  "steps": [
    "Read the `Prerequisites and Access` section of `PROJECT_ROOT/.agent/prd/PRD-001.md` and list required database access, MCPs, service docs, environment variable names, login/test users, and open gaps",
    "Confirm `PROJECT_ROOT/.env.local` exists and contains every required environment variable name; add missing names with placeholder values only, such as `TODO_FILL_MANUALLY`",
    "Ask the user to confirm they filled real local values where needed; never print, store, commit, or copy actual secrets",
    "Run the safest available read-only connectivity checks for the database and required services; record any blocker or user-approved proceed decision",
    "Confirm required MCP servers/tools are available and authenticated, and that required documentation links are accessible",
    "Confirm required login/test users exist with the needed roles, or document the exact steps and owner for creating/requesting them"
  ],
  "depends_on": [],
  "verify": [],
  "estimatedComplexity": "low",
  "technicalNotes": [
    "This task gates implementation. Do not start dependent feature tasks until required prerequisites are verified or explicitly approved as gaps.",
    "Secrets must stay local and must never be committed or copied into PRD/task artifacts."
  ]
}
```

## Root task list format

Each task in the index must follow this structure (notice: **no `prd` field in `tasks.json`**):

```json:PROJECT_ROOT/.agent/tasks.json
[
  {
    "id": "TASK-1",
    "title": "Clear, concise title of the task",
    "category": "setup | feature | refactor | test",
    "specFilePath": ".agent/tasks/TASK-1.json",
    "priority": 1,
    "depends_on": [],
    "status": "pending"
  },
  {
    "id": "TASK-2",
    "title": "Feature implementation building on prerequisites",
    "category": "feature",
    "specFilePath": ".agent/tasks/TASK-2.json",
    "priority": 2,
    "depends_on": ["TASK-1"],
    "status": "pending"
  }
]
```

**Field Requirements:**

- `id`: Unique identifier for the task, formatted as `TASK-${ID}`
- `title`: A title that gives a high-level overview of the task
- `category`: Classification of task type (setup, feature, refactor, test, ui-ux, data-model, api-endpoint, security, etc.)
- `specFilePath`: Path to the individual task specification file, formatted as `.agent/tasks/TASK-${ID}.json`
- `priority`: Priority number (lower integer = higher priority, used by deterministic selector)
- `depends_on`: Explicit array of prerequisite task IDs that must have `status: "completed"` before this task is runnable. MUST be present on all tasks (use `[]` if no dependencies).
- `status`: Always initialize to `"pending"`. The host orchestrator manages transitions to `"completed"`. (Do NOT set `"in_progress"` during generation — it is a runtime-only state managed by the loop).

## Individual JSON Task Format

Each task specification file provides comprehensive details for implementation. The root `tasks.json` is the index; `TASK-${ID}.json` contains the execution spec, including the `prd` field linking to the owning PRD document.

```json:PROJECT_ROOT/.agent/tasks/TASK-${ID}.json
{
  "id": "TASK-${ID}",
  "title": "Clear, concise title of the task",
  "category": "category-name",
  "prd": ".agent/prd/PRD-001.md",
  "description": "In-depth specification including expected behavior, user flow, and output",
  "acceptance_criteria": [
    "List of specific, verifiable conditions that must be true when task is complete"
  ],
  "steps": [
    "First action, with the exact file or command",
    "Second action, including how to verify it"
  ],
  "depends_on": ["TASK-${ID1}", "TASK-${ID2}"],
  "verify": [
    { "repo": "simple-notes-api", "commands": ["npm test", "npm run build"] }
  ],
  "estimatedComplexity": "medium",
  "technicalNotes": [
    "List of technical notes, implementation hints, or technical constraints developers should know"
  ]
}
```

### Required Fields

| Field                 | Type             | Description                                                                     |
| --------------------- | ---------------- | ------------------------------------------------------------------------------- |
| `id`                  | string           | Unique identifier, formatted as `TASK-${ID}`                                    |
| `title`               | string           | High-level overview of the task (same as in tasks.json)                         |
| `category`            | string           | Classification of task type                                                     |
| `description`         | string           | In-depth specification including expected behavior, user flow, and output       |
| `acceptance_criteria` | array of strings | List of specific, verifiable conditions that must be true when task is complete |
| `steps`               | array of strings | Sequential actions, each naming the file or command involved                    |
| `depends_on`          | array of strings | Explicit array of prerequisite task IDs (`[]` if none)                          |

### Optional Fields

| Field                 | Type                      | Description                                                                      |
| --------------------- | ------------------------- | -------------------------------------------------------------------------------- |
| `prd`                 | string                    | File path to the source PRD document (e.g. `.agent/prd/PRD-001.md`)               |
| `verify`              | array of repo/command sets | Commands the coder runs before committing and the reviewer re-runs before PASS    |
| `estimatedComplexity` | string                    | One of: `"low"`, `"medium"`, `"high"`, `"very high"` - helps with planning       |
| `technicalNotes`      | array of strings          | Implementation hints, gotchas, or technical constraints developers should know   |

### Verify Field Format

```json
"verify": [
  { "repo": "simple-notes-api", "commands": ["npm test", "npm run build"] },
  { "repo": "*", "commands": ["make lint"] }
]
```

- `repo` is a directory name under `workspace/`. `"*"` runs the commands in every repo the task touches.
- Commands run with the task worktree as cwd, never the operator's checkout.
- Omit `verify` when the project has no useful check; the coder then derives the project's own commands and the reviewer records what it actually ran.
- Keep commands fast and deterministic. Do not put commands that need services that only exist outside a worktree (a docker-compose stack, a shared database).

### Dependency Resolution Rules

Deterministic task selection requires valid dependency graphs:
1. Every task MUST have an explicit `depends_on` array (`[]` if none).
2. All referenced IDs in `depends_on` must exist in `tasks.json`.
3. No circular dependency loops allowed.
4. Downstream tasks are selected only after ALL items in `depends_on` have reached `status: "completed"`.

### Initialize All Tasks to `"status": "pending"`

**CRITICAL**: Never mark tasks as completed during generation. The `status` field must ALWAYS be `"pending"` initially.

Do NOT specify `"in_progress"` in task definitions; that state is strictly set and cleared by `ralph.sh` at runtime.

## Output Format

Save the complete task list as `PROJECT_ROOT/.agent/tasks.json` and each spec as `PROJECT_ROOT/.agent/tasks/TASK-${ID}.json`.

```json
[
  {
    "id": "TASK-1",
    "title": "Verify project prerequisites and access",
    "category": "setup",
    "specFilePath": ".agent/tasks/TASK-1.json",
    "priority": 1,
    "depends_on": [],
    "status": "pending"
  },
  {
    "id": "TASK-2",
    "title": "User table with authentication fields",
    "category": "data-model",
    "specFilePath": ".agent/tasks/TASK-2.json",
    "priority": 2,
    "depends_on": ["TASK-1"],
    "status": "pending"
  }
]
```

## After Generation

Present the tasks to the user:

"I've generated [NUMBER] implementation tasks based on your PRD with explicit dependency ordering and initial status set to 'pending'.

Each task runs on its own branch cut from the PRD branch (`{type}/{slug}`) and is reviewed by an independent reviewer before it can merge. Tasks are saved in `PROJECT_ROOT/.agent/tasks.json`; Ralph will:
1. Select tasks deterministically based on priority and satisfied `depends_on`
2. Implement each one in its own worktree
3. Mark tasks `status: "completed"` only after the reviewer passes and the task branch merges
4. Never remove or skip tasks"
