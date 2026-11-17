# Implementation Task Generation

Transform the completed PRD into simple, concise, actionable and verifiable implementation tasks in JSON format. This creates a comprehensive task list for developers (human or AI) to build and verify the product.

## When to Use

After completing PRD creation, ask the user:
"Your PRD is complete. Would you like me to generate implementation tasks? I'll create a comprehensive JSON task list that breaks down all features into verifiable development work."

Only proceed after user confirmation.

## Task Generation Workflow

You should read the PRD markdown file located in `PROJECT_ROOT/.agent/prd/PRD.md`.
Each task in the PRD will have a unique ID, formatted as `TASK-${ID}`.
Use those IDs to generate the task list. If the PRD has a `Prerequisites and Access` section, `TASK-1` is reserved for prerequisite verification. If no prerequisites section exists, skip `TASK-1` and start with feature tasks.

Copy and track progress:

```
Task Generation Progress:
- [ ] Analyze the complete PRD
- [ ] Generate prerequisite verification task (optional, only if PRD has prerequisites)
- [ ] Generate task index in `PROJECT_ROOT/.agent/tasks.json`
- [ ] Generate detailed spec for each task in `PROJECT_ROOT/.agent/tasks/TASK-${ID}.json`
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
  "description": "Verify that required database access, MCPs, service documentation, environment variables, and login/test users are available before implementation begins.",
  "acceptanceCriteria": [
    "`PROJECT_ROOT/.env.local` exists with placeholder entries for every required environment variable name listed in the PRD",
    "Real secret values are not written to the PRD, task specs, repository, logs, or chat",
    "The user has manually filled required local secret values in `.env.local` where needed",
    "Database connectivity is verified, or the missing access is recorded with a user-approved proceed/block decision",
    "Required MCP servers/tools are installed and authenticated, or gaps are recorded with a user-approved proceed/block decision",
    "Required service documentation links are available to the implementer",
    "Required login/test users are available or documented with request/create steps, without passwords or secret values"
  ],
  "steps": [
    {
      "step": 1,
      "description": "Read prerequisite requirements from the PRD",
      "details": "Open `PROJECT_ROOT/.agent/prd/PRD.md` and review the `Prerequisites and Access` section. List required database access, MCPs, service docs, environment variable names, login/test users, and any open gaps.",
      "status": "pending"
    },
    {
      "step": 2,
      "description": "Verify `.env.local` placeholder names",
      "details": "Confirm `PROJECT_ROOT/.env.local` exists and contains every required environment variable name from the PRD. Add missing names with placeholder values only, such as `TODO_FILL_MANUALLY`. Do not write real secret values.",
      "status": "pending"
    },
    {
      "step": 3,
      "description": "Confirm local secret values are filled manually",
      "details": "Ask the user to confirm they filled real local values where needed. Never print, store, commit, or copy actual passwords, API keys, tokens, or connection strings into generated files or chat.",
      "status": "pending"
    },
    {
      "step": 4,
      "description": "Verify database and service access",
      "details": "Run the safest available read-only connectivity checks for the database and required services. If access cannot be verified, record the blocker or user-approved proceed decision before continuing.",
      "status": "pending"
    },
    {
      "step": 5,
      "description": "Verify MCPs and service documentation",
      "details": "Confirm required MCP servers/tools are available and authenticated. Confirm required documentation links from the PRD are accessible and sufficient for implementation.",
      "status": "pending"
    },
    {
      "step": 6,
      "description": "Verify login/test user availability",
      "details": "Confirm required login/test users exist with the needed roles and permissions, or document the exact steps and owner for creating/requesting them. Do not store passwords or secret values.",
      "status": "pending"
    }
  ],
  "depends_on": [],
  "estimatedComplexity": "low",
  "technicalNotes": [
    "This task gates implementation. Do not start dependent feature tasks until required prerequisites are verified or explicitly approved as gaps.",
    "Secrets must stay local and must never be committed or copied into PRD/task artifacts."
  ]
}
```

## Root task list format

Each task in the index must follow this structure:

```json:PROJECT_ROOT/.agent/tasks.json
[
  {
    "id": "TASK-1",
    "title": "Clear, concise title of the task",
    "category": "setup | feature | refactor | test",
    "specFilePath": ".agent/tasks/TASK-1.json",
    "prd": ".agent/prd/PRD.md#section-anchor",
    "priority": 1,
    "depends_on": [],
    "status": "pending"
  },
  {
    "id": "TASK-2",
    "title": "Feature implementation building on prerequisites",
    "category": "feature",
    "specFilePath": ".agent/tasks/TASK-2.json",
    "prd": ".agent/prd/PRD.md#section-anchor",
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
- `prd`: Optional link or section anchor in the PRD (e.g., `.agent/prd/PRD.md#auth`)
- `priority`: Priority number (lower integer = higher priority, used by deterministic selector)
- `depends_on`: Explicit array of prerequisite task IDs that must have `status: "completed"` before this task is runnable. MUST be present on all tasks (use `[]` if no dependencies).
- `status`: Always initialize to `"pending"`. The host orchestrator manages transitions to `"completed"`. (Do NOT set `"in_progress"` during generation — it is a runtime-only state managed by the loop).

## Individual JSON Task Format

Each task specification file provides comprehensive details for implementation. The root `tasks.json` is the index; `TASK-${ID}.json` contains the execution spec.

```json:PROJECT_ROOT/.agent/tasks/TASK-${ID}.json
{
  "id": "TASK-${ID}",
  "title": "Clear, concise title of the task",
  "category": "category-name",
  "prd": ".agent/prd/PRD.md#section-anchor",
  "description": "In-depth specification including expected behavior, user flow, and output",
  "acceptanceCriteria": [
    "List of specific, verifiable conditions that must be true when task is complete"
  ],
  "steps": [
    {
      "step": 1,
      "description": "Short description of what to do",
      "details": "Detailed explanation of HOW to do it, including specific code, commands, or techniques",
      "status": "pending"
    }
  ],
  "depends_on": ["TASK-${ID1}", "TASK-${ID2}"],
  "estimatedComplexity": "medium",
  "technicalNotes": [
    "List of technical notes, implementation hints, or technical constraints developers should know"
  ]
}
```

### Required Fields

| Field                | Type                  | Description                                                                     |
| -------------------- | --------------------- | ------------------------------------------------------------------------------- |
| `id`                 | string                | Unique identifier, formatted as `TASK-${ID}`                                    |
| `title`              | string                | High-level overview of the task (same as in tasks.json)                         |
| `category`           | string                | Classification of task type                                                     |
| `description`        | string                | In-depth specification including expected behavior, user flow, and output       |
| `acceptanceCriteria` | array of strings      | List of specific, verifiable conditions that must be true when task is complete |
| `steps`              | array of step objects | Sequential implementation steps (see step format below)                         |
| `depends_on`         | array of strings      | Explicit array of prerequisite task IDs (`[]` if none)                          |

### Optional Fields

| Field                 | Type             | Description                                                                      |
| --------------------- | ---------------- | -------------------------------------------------------------------------------- |
| `prd`                 | string           | Section anchor or path in the PRD (e.g. `.agent/prd/PRD.md#db`)                  |
| `estimatedComplexity` | string           | One of: `"low"`, `"medium"`, `"high"`, `"very high"` - helps with planning       |
| `technicalNotes`      | array of strings | Implementation hints, gotchas, or technical constraints developers should know   |

### Step Object Format

Each step in the `steps` array must be an object with these fields:

```json
{
  "step": 1,
  "description": "Short description of what to do",
  "details": "Detailed explanation of HOW to do it, including specific code, commands, or techniques",
  "status": "pending"
}
```

| Field         | Type   | Description                                                                     |
| ------------- | ------ | ------------------------------------------------------------------------------- |
| `step`        | number | Sequential step number (1, 2, 3...)                                             |
| `description` | string | Brief summary of the step (what to do)                                          |
| `details`     | string | Comprehensive implementation guidance (how to do it)                            |
| `status`      | string | Always initialize to `"pending"` - updated to `"completed"` once verified done |

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

The tasks are saved in `PROJECT_ROOT/.agent/tasks.json`. Developers/Ralph will:
1. Select tasks deterministically based on priority and satisfied `depends_on`
2. Mark tasks `status: "completed"` after all verification steps pass
3. Never remove or skip tasks"
