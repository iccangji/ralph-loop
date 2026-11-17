# Ralph Loop

Autonomous agent loop. `ralph.sh` runs the `pi` coding agent inside an
ephemeral Docker container against the repository in `workspace/`, one task
per iteration, until every entry in `.agent/tasks.json` has `passes: true`.

## Agent Role: Managing Orchestrator

The agent reading this repository (running in Antigravity or another harness) acts strictly as a **Manager and Orchestrator** for the autonomous loop:

- **Scope boundary: Task Management Only**: The manager's duties are strictly limited to planning, defining, refining, and validating `.agent/tasks.json` and `.agent/tasks/TASK-*.json` specs, PRD, and architecture documentation.
- **Do NOT execute `./ralph.sh` autonomously**: Do NOT run `./ralph.sh` or trigger the agent loop unless the human partner explicitly commands to run it (e.g. "jalankan ralph", "run ralph.sh").
- **Do NOT directly edit `workspace/` code**: Direct workspace code edits are strictly prohibited. Implementation belongs entirely to the `pi` agent running inside the Docker sandbox.
- **Priority #1 is always `.agent/tasks.json`**: Inspect `tasks.json` and `.agent/tasks/TASK-*.json` first before answering questions, planning next steps, or touching control files.
- **Execution belongs to `pi`**: The `pi` container launched by `./ralph.sh` is the execution worker. The manager prepares clear, self-contained task specs with accurate `depends_on` chains, reviews execution logs when finished, and resolves `BLOCKED` or `DECIDE` requests.

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

### 2. Task Specification: `$AGENT_DIR/tasks/TASK-{ID}.json`

Comprehensive execution details for a single task:

```json
{
  "id": "TASK-001",
  "title": "Short title describing the task",
  "category": "setup | feature | refactor | test",
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

### 3. Task Execution Rules

- The managing agent defines and reviews tasks in these files, ensuring dependencies (`depends_on`) form a valid Directed Acyclic Graph (DAG).
- The `pi` agent selects the highest-priority task where `passes: false` AND all task IDs in `depends_on` have `passes: true`.
- Once finished, the container commits changes in `workspace/` and outputs `<promise>TASK-{ID}:DONE</promise>`.
- The host flips `passes: true`, updates `LOG.md`, and commits to this repository.

## Runtime model

```
host (ralph.sh)                     container (ephemeral, host UID/GID)
  parse args                          $SCRIPT_DIR/workspace  RW  ← same path as host
  preflight checks                    $SCRIPT_DIR/.agent     RO
  build image (once, cached)          $SCRIPT_DIR/.agents    RO
  docker run ───────────────────────→ /pi-config             RO  (.pi/)
  read JSONL, spinner, preview        /home/pi/.gitconfig    RO
  mark task done, commit              /var/run/docker.sock   host daemon
  refresh graph                       pi --mode json --approve --no-session
  tear down project stack             → <promise>TASK-x:DONE</promise>
```

The workspace is mounted at the **same absolute path** it has on the host. That
is deliberate: compose files with relative bind mounts (`./service-a:/app`) are
resolved by the host daemon, so a `/workspace` mount would point it at a path
that does not exist.

`$AGENT_DIR` points to the host's `.agent/` directory, mounted read-only.
Global skills are mounted to `/home/pi/.agents` so `pi` discovers them
regardless of the workspace location.

Host is the orchestrator and the only owner of task state. The container is
throwaway: it starts, does one task, commits, prints a promise tag, and dies.

## Hard invariants

Do not break these without an explicit request.

1. **Docker is the only runtime.** `sbx` / Docker Sandboxes was removed; do
   not reintroduce it.
2. **`pi` is the only supported agent.** `SUPPORTED_AGENTS` in
   `scripts/lib/agents.sh` reflects that.
3. **The workspace is the only writable mount inside the agent container.**
   `.agent/`, `.agents/`, `.pi/`, and `~/.gitconfig` are read-only. The agent
   can still write elsewhere through the Docker socket; that is accepted.
4. **Host owns `.agent/tasks.json` and `.agent/logs/LOG.md`.** The managing
   agent inspects and manages tasks here; the container sees them read-only.
   The `pi` agent only emits promise tags; `scripts/lib/tasks.sh` flips
   `passes`, appends the log, and commits in this repo.
5. **No direct workspace modifications by managing agent.** All implementation
   work in `workspace/` must be performed through tasks executed by the `pi`
   agent container via `ralph.sh`.
6. **No autonomous `./ralph.sh` execution.** The managing agent must only prepare
   and manage tasks; it must never run `./ralph.sh` unless explicitly ordered
   by the user.
7. **No browser, no Playwright, no `sudo`, no runtime system installs.** Tool
   additions belong in `Dockerfile.pi`, which pins the agent version.
8. **pi config comes from project `.pi/` only**, never from `$HOME`.
9. **`workspace/` is its own git repository**, not part of this repo. A
   multi-repo layout (one repo per service) is also valid.
10. **Unknown CLI flags must error**, not be ignored.
11. **The Docker socket is mounted on purpose.** The agent manages service
    containers with `docker compose`, which grants host-root equivalent access.
    Only run Ralph on a host you can throw away.

## Module map

| File                                                                      | Responsibility                                                                  |
| ------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `ralph.sh`                                                                | Arg wiring, preflight order, iteration loop, exit codes                         |
| `scripts/lib/args.sh`                                                     | Flag parsing (`--once`, `-n`, `--agent`, `--`, `--help`)                        |
| `scripts/lib/constants.sh`                                                | Version, image tag, `EXIT_*` codes                                              |
| `scripts/lib/docker.sh`                                                   | Image build, provider check, socket mount, stack teardown, `docker run` builder |
| `scripts/lib/agents.sh`                                                   | Agent registry, container naming, `build_agent_command`                         |
| `scripts/lib/preflight.sh`                                                | Workspace git check, required files                                             |
| `scripts/lib/output.sh`                                                   | pi JSONL parsing, summary extraction, complete-line offset                      |
| `scripts/lib/promise.sh`                                                  | `<promise>` tag detection and extraction                                        |
| `scripts/lib/tasks.sh`                                                    | `mark_task_complete`, `all_tasks_passed`                                        |
| `scripts/lib/graphify.sh`                                                 | Host-side `graphify update` after completion                                    |
| `scripts/lib/cleanup.sh`                                                  | Signal handling, container and temp-file cleanup                                |
| `scripts/lib/{spinner,preview,timing,display,notify,terminal,logging}.sh` | UI only                                                                         |

`scripts/docker-entrypoint.sh` copies `/pi-config` into the writable
`/home/pi/.pi/agent`, writes `trust.json` for the current workspace path, then
`exec pi "$@"`.

## Per-iteration flow

1. Build the prompt from `.agent/PROMPT.md` with `PROJECT_ROOT` set to
   `$SCRIPT_DIR/workspace` (also exported into the container, so the prompt's
   `$PROJECT_ROOT` works when pasted into a shell).
2. Run the container under a pseudo-TTY (`script`), capture JSONL to a temp file.
3. Consume **only complete lines** (`last_complete_line_offset`) so a partial
   record never loses text.
4. Feed parsed text to spinner and preview; keep a cleaned transcript in
   `.agent/history/ITERATION-*.txt`.
5. On `<promise>TASK-x:DONE</promise>`: mark the task, log it, commit here.
6. Refresh `workspace/graphify-out/` on the host (skipped if `graphify` absent).
7. Tear down the project stack (`down_project_stack`) so service containers the
   agent started do not outlive the iteration.
8. Stop on `COMPLETE`, `BLOCKED` (exit 2), `DECIDE` (exit 3), or max iterations.

## Verifying changes

There is no test suite and no CI. Verify by hand:

```bash
bash -n ralph.sh && for f in scripts/lib/*.sh; do bash -n "$f"; done
```

- **Module change** → source the module in a throwaway dir under `/tmp` with
  `SCRIPT_DIR` set, then call the function and inspect the result.
- **Mount or command change** → build the image and run `docker run` directly,
  confirming: the workspace path is writable, `.agent` returns
  `Read-only file system`, `git config user.name` resolves, `docker ps` works,
  provider reachable.
- **Full loop** → copy the repo to a `/tmp` fixture, `git init` its `workspace/`,
  add one real task, then `./ralph.sh --once`.

The model behind `9Router/combo1` is slow (a trivial call can take ~70s), so
full-loop runs need generous timeouts. A short timeout is not a failure signal.

## Known gotchas

- pi writes `*.lock` files next to its config, so the agent dir must be
  writable. A read-only `/pi-agent` mount fails with `EROFS`.
- The agent runs as the host UID/GID, so the socket mount needs
  `--group-add $(stat -c %g /var/run/docker.sock)`. Without it every `docker`
  call fails with `permission denied`.
- `COMPOSE_PROJECT_NAME` is injected as `ralph-<hash>` and beats a compose
  file's `name:`. That is how `down_project_stack` finds the stack; never pass
  `-p` inside the agent.
- `IMAGE_REVISION` in `scripts/lib/constants.sh` must be bumped whenever
  `Dockerfile.pi` changes. `ensure_pi_image` only builds when the tag is
  missing, so a stale tag silently keeps the old image.
- pi only reads project MCP config after project trust, hence `trust.json`.
- Skills are discovered from `.agents/skills` (canonical). `.agent/skills` and
  `.claude/skills` are relative symlinks.
- `.pi/models.json` is gitignored.
- `graphify` runs on the host only. The agent may read
  `workspace/graphify-out/GRAPH_REPORT.md` but cannot query the CLI.
- Debian's Python is PEP 668 marked, so any Python tooling needs a venv plus
  `python3-venv`; plain `pip install` is rejected.
- `ralph.sh` is ~350 lines, above the 300-line guidance. Split it only when
  you are already changing the loop body.

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

- **One task per invocation.** The managing agent (running this harness) reads `$AGENT_DIR/tasks.json` and manages context. Do not immediately modify workspace code upon receiving an instruction; read `$AGENT_DIR/tasks.json` and task specs first to understand the execution plan. The `pi` agent inside Docker executes one task per invocation, commits, and reports back via promise tags.
- **Role of the managing agent.** The host/managing agent acts as a manager and orchestrator for the `pi` agent in Docker. It does not perform workspace code edits directly when task-driven execution is active; it plans, reviews tasks, and delegates execution to the `pi` container iterations.

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
