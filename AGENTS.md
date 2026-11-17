# Ralph Loop

Autonomous agent loop. `ralph.sh` runs an agent CLI (`opencode` by default,
`pi` as an alternative) directly on the host against the repository in
`workspace/`, one task per iteration, until every entry in `.agent/tasks.json`
has `passes: true`.

## Agent Role: Managing Orchestrator

The agent reading this repository (running in Antigravity or another harness) acts strictly as a **Manager and Orchestrator** for the autonomous loop:

- **Scope boundary: Task Management Only**: The manager's duties are strictly limited to planning, defining, refining, and validating `.agent/tasks.json` and `.agent/tasks/TASK-*.json` specs, PRD, and architecture documentation.
- **Do NOT execute `./ralph.sh` autonomously**: Do NOT run `./ralph.sh` or trigger the agent loop unless the human partner explicitly commands to run it (e.g. "jalankan ralph", "run ralph.sh").
- **Do NOT directly edit `workspace/` code**: Direct workspace code edits are strictly prohibited. Implementation belongs entirely to the agent CLI running on the host.
- **Priority #1 is always `.agent/tasks.json`**: Inspect `tasks.json` and `.agent/tasks/TASK-*.json` first before answering questions, planning next steps, or touching control files.
- **Execution belongs to the agent CLI**: the `opencode` (default) or `pi` process launched by `./ralph.sh` is the execution worker. The manager prepares clear, self-contained task specs with accurate `depends_on` chains, reviews execution logs when finished, and resolves `BLOCKED` or `DECIDE` requests.

## Task Structure & Lifecycle

The project uses a two-tier task structure stored under `$AGENT_DIR`:

### 1. Task Index: `$AGENT_DIR/tasks.json`

An array of task summary items representing the execution queue:

```json
[
  {
    "id": "TASK-001",
    "title": "Short title describing the task",
    "category": "setup | feature | refactor | test",
    "specFilePath": ".agent/tasks/TASK-001.json",
    "prd": ".agent/prd/PRD.md#section-anchor",
    "priority": 1,
    "depends_on": [],
    "passes": false
  },
  {
    "id": "TASK-002",
    "title": "Feature implementation building on 001",
    "category": "feature",
    "specFilePath": ".agent/tasks/TASK-002.json",
    "priority": 2,
    "depends_on": ["TASK-001"],
    "passes": false
  }
]
```

- `id` _(string, required)_: Identifier matching `TASK-[A-Za-z0-9._-]+`.
- `title` _(string, required)_: Human-readable task title. Appended to `LOG.md` when completed.
- `passes` _(boolean, required)_: `false` initially. Updated to `true` exclusively by the host orchestrator (`tasks.sh`) when `<promise>TASK-x:DONE</promise>` is observed.
- `priority` _(number, optional)_: Priority order (lower integer = higher priority).
- `depends_on` _(array of strings, optional)_: List of task IDs that must have `passes: true` before this task can be selected. An agent picking tasks must evaluate this dependency chain.
- `specFilePath` _(string, optional)_: Path to detailed specification file.
- `prd` _(string, optional)_: Path to PRD doc or section anchor relevant to this task (e.g. `.agent/prd/PRD.md#user-auth`).

### 2. Task Specification: `$AGENT_DIR/tasks/TASK-{ID}.json`

Comprehensive execution details for a single task:

```json
{
  "id": "TASK-001",
  "title": "Short title describing the task",
  "category": "setup | feature | refactor | test",
  "prd": ".agent/prd/PRD.md#section-anchor",
  "description": "Full description of what needs to be implemented and why.",
  "depends_on": [],
  "steps": [
    "Step-by-step instructions for implementation",
    "Specific commands to execute or files to create/edit",
    "Verification tests to run"
  ],
  "acceptance_criteria": [
    "Specific verifiable assertion 1",
    "Specific verifiable assertion 2"
  ]
}
```

- `prd` _(string, optional)_: Context link to the relevant PRD requirement or design spec for this task.

### 3. Task Execution Rules

- The managing agent defines and reviews tasks in these files, ensuring dependencies (`depends_on`) form a valid Directed Acyclic Graph (DAG).
- The agent CLI selects the highest-priority task where `passes: false` AND all task IDs in `depends_on` have `passes: true`.
- Once finished, the agent commits changes in `workspace/` and outputs `<promise>TASK-{ID}:DONE</promise>`.
- The host flips `passes: true`, updates `LOG.md`, and commits to this repository.

## Runtime model

```
host (ralph.sh)                     agent CLI (host process, operator's user)
  parse args                          cwd = $SCRIPT_DIR/workspace
  preflight checks                    $SCRIPT_DIR/.agent          (prompt reads it)
  prepare run state ────────────────→ $SCRIPT_DIR/.agents/skills  (explicit)
  read JSONL, spinner, preview        temp agent dir / temp session DB
  mark task done, commit              opencode: --standalone, OPENCODE_DB
  refresh graph                       pi: copied .pi/, generated trust.json
  tear down project stack             → <promise>TASK-x:DONE</promise>
```

There is no sandbox and no mount translation: the agent sees the same paths the
host does. The workspace may be one git repo or one repo per service; the agent
commits inside the repo that owns the changed files.

`$AGENT_DIR` is the host's `.agent/` directory. The agent is instructed not to
write there; opencode additionally enforces workspace-only edits with permission
rules, while `pi` relies on the prompt.

Each run gets a temporary state directory (`mktemp -d`) that is deleted on exit:
opencode gets a throwaway `OPENCODE_DB`; pi gets a copy of `.pi/` and a
`trust.json` that trusts only the workspace.

Host is the orchestrator and the only owner of task state. The agent process is
throwaway: it starts, does one task, commits, prints a promise tag, and exits.

## Hard invariants

Do not break these without an explicit request.

1. **Agents run on the host.** There is no container or sandbox runtime; do not
   reintroduce one.
2. **`opencode` (default) and `pi` are the supported agents.**
   `SUPPORTED_AGENTS` in `scripts/lib/agents.sh` reflects that.
3. **Workspace-only writes are a rule, not a mount.** opencode enforces it with
   `external_directory` permission rules; `pi` follows the prompt. Nothing
   prevents a determined agent from writing elsewhere.
4. **Host owns `.agent/tasks.json` and `.agent/logs/LOG.md`.** The managing
   agent inspects and manages tasks here; the agent is told not to write them.
   The agent only emits promise tags; `scripts/lib/tasks.sh` flips `passes`,
   appends the log, and commits in this repo.
5. **No direct workspace modifications by managing agent.** All implementation
   work in `workspace/` must be performed through tasks executed by the agent
   via `ralph.sh`.
6. **No autonomous `./ralph.sh` execution.** The managing agent must only prepare
   and manage tasks; it must never run `./ralph.sh` unless explicitly ordered
   by the user.
7. **Browsers and `sudo` are allowed; global tooling installs are not.** Do not
   add runtime system installs to satisfy a task. Tool additions belong to the
   project or to `.agents/skills`.
8. **Agent config is project-owned.** `opencode.jsonc` is tracked at the repo
   root (model pin plus permission rules). `pi` reads a per-run copy of the
   gitignored `.pi/` directory.
9. **`workspace/` is not part of this repo.** A single-repo layout and a
   multi-repo layout (one repo per service) are both valid.
10. **Unknown CLI flags must error**, not be ignored.
11. **Docker is optional.** It is used only for project service stacks and
    teardown. Never make an agent run depend on Docker being installed.

## Module map

| File                                                                      | Responsibility                                                                  |
| ------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `ralph.sh`                                                                | Arg wiring, preflight order, iteration loop, exit codes                         |
| `scripts/lib/args.sh`                                                     | Flag parsing (`--once`, `-n`, `--agent`, `--`, `--help`)                        |
| `scripts/lib/constants.sh`                                                | Version, minimum agent versions, `EXIT_*` codes                                 |
| `scripts/lib/agents.sh`                                                   | Agent registry, version gate, per-run state, command builder                    |
| `scripts/lib/stack.sh`                                                    | Optional compose project name and stack teardown                                |
| `scripts/lib/preflight.sh`                                                | Agent/config/provider checks, workspace git check, required files              |
| `scripts/lib/output.sh`                                                   | Per-agent JSONL parsing, summary extraction, complete-line offset               |
| `scripts/lib/promise.sh`                                                  | `<promise>` tag detection and extraction                                        |
| `scripts/lib/tasks.sh`                                                    | `mark_task_complete`, `all_tasks_passed`                                        |
| `scripts/lib/graphify.sh`                                                 | Host-side `graphify update` after completion                                    |
| `scripts/lib/cleanup.sh`                                                  | Signal handling, agent process and temp-state cleanup                           |
| `scripts/lib/{spinner,preview,timing,display,notify,terminal,logging}.sh` | UI only                                                                         |

## Per-iteration flow

1. Build the prompt from `.agent/PROMPT.md` with `PROJECT_ROOT` set to
   `$SCRIPT_DIR/workspace` and `AGENT_DIR` to `$SCRIPT_DIR/.agent`.
2. Prepare run state: temp dir, pi config copy or opencode session DB, and the
   per-run workspace skill link.
3. Run the agent CLI directly on the host, capture stdout and stderr to a temp
   file.
4. Consume **only complete lines** (`last_complete_line_offset`) so a partial
   record never loses text.
5. Feed parsed text to spinner and preview; keep a cleaned transcript in
   `.agent/history/ITERATION-*.txt`.
6. On `<promise>TASK-x:DONE</promise>`: mark the task, log it, commit here.
7. Refresh `workspace/graphify-out/` on the host (skipped if `graphify` absent).
8. Tear down the project stack (`down_project_stack`) so service containers the
   agent started do not outlive the iteration.
9. Stop on `COMPLETE`, `BLOCKED` (exit 2), `DECIDE` (exit 3), or max iterations.

## Verifying changes

There is no test suite and no CI. Verify by hand:

```bash
bash -n ralph.sh && for f in scripts/lib/*.sh; do bash -n "$f"; done
```

- **Module change** → source the module in a throwaway dir under `/tmp` with
  `SCRIPT_DIR` set, then call the function and inspect the result.
- **Command or state change** → run the built command directly from
  `workspace/`, confirming: the agent starts, the provider answers, the temp
  state dir is used, and `opencode debug config` shows the tracked config.
- **Full loop** → copy the repo to a `/tmp` fixture, `git init` its `workspace/`,
  add one real task, then `./ralph.sh --once`.

The model behind `9Router/combo1` is slow (a trivial call can take ~70s), so
full-loop runs need generous timeouts. A short timeout is not a failure signal.

## Known gotchas

- opencode auto-rejects tool calls in non-interactive mode unless `--auto` is
  passed. Ralph always passes it; the permission rules still win over `--auto`.
- opencode `--archived` is metadata only. Real isolation needs `--standalone`
  plus a throwaway `OPENCODE_DB` (what Ralph does), at the cost of ~6-9s per
  iteration.
- opencode discovers project config from the cwd and its ancestors, so the
  repo-root `opencode.jsonc` applies when cwd is `workspace/`. Preflight fails
  closed if the model pin or `external_directory` rule is not loaded.
- opencode permission resources match the whole subcommand string with globs,
  last match wins. `external_directory` does not block absolute paths inside
  shell commands.
- pi does not read project `.pi/models.json`; `PI_CODING_AGENT_DIR` is the only
  lever. Ralph points it at a per-run copy.
- pi project trust lives in `trust.json` inside the agent dir; Ralph trusts only
  the workspace path.
- `COMPOSE_PROJECT_NAME` is injected as `ralph-<hash>` and beats a compose
  file's `name:`. That is how `down_project_stack` finds the stack; never pass
  `-p` inside the agent.
- Skills are canonical in `.agents/skills`; `.agent/skills` and `.claude/skills`
  are relative symlinks to it. `pi` gets `--skill .agents/skills`; opencode
  discovers `.opencode/skills`, which Ralph links to the canonical dir for the
  run and removes afterwards.
- `.pi/models.json` and `.pi/settings.json` are gitignored. The `.pi/` directory
  itself is tracked.
- `graphify` runs on the host only. The agent may read
  `workspace/graphify-out/GRAPH_REPORT.md` but cannot query the CLI.
- Debian's Python is PEP 668 marked, so any Python tooling needs a venv plus
  `python3-venv`; plain `pip install` is rejected.
- `ralph.sh` is ~370 lines, above the 300-line guidance. Split it only when you
  are already changing the loop body.

# Code Quality Standards

Always apply these standards to all code you write.

## Reuse Before Creating

Before writing new code, analyze existing utilities, components, hooks, helpers and tests:

1. **Search first** — grep/glob for similar functionality before implementing
2. **Extend if close** — if something exists that's 80% of what you need, extend it
3. **Extract if duplicating** — if you're about to copy-paste, extract to shared module instead

## File Size & Organization

Keep files between **200-300 lines max**. If a file exceeds this:

1. **Split by responsibility** — one module = one concern
2. **Extract sub-components** — UI pieces that can stand alone should
3. **Separate logic from presentation** — hooks/utils in their own files
4. **Group by feature** — co-locate related files, not by type

Signs a file needs splitting:

- Multiple unrelated exports
- Scrolling to find what you need
- "Utils" file becoming a junk drawer
- Component doing data fetching + transformation + rendering

## Task Execution

- **One task per invocation.** The managing agent (running this harness) reads `$AGENT_DIR/tasks.json` and manages context. Do not immediately modify workspace code upon receiving an instruction; read `$AGENT_DIR/tasks.json` and task specs first to understand the execution plan. The agent CLI executes one task per invocation, commits, and reports back via promise tags.
- **Role of the managing agent.** The host/managing agent acts as a manager and orchestrator for the agent CLI. It does not perform workspace code edits directly when task-driven execution is active; it plans, reviews tasks, and delegates execution to the agent iterations.

## Execution Guidelines

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

### 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:

- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:

- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:

- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

### 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:

- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:

```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

## Code Style

1. Prefer writing clear code and use inline comments sparingly
2. Document methods with block comments at the top of the method
3. Use Conventional Commit format

## Test To Verify Functionality

If you didn't test it, it doesn't work.

Verify written code by:

- Running unit tests
- Running end to end tests
- Checking for type errors
- Checking for lint errors
- Smoke testing the running app with `curl` and checking for runtime errors
