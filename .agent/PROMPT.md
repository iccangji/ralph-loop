> ⛔ **ONE TASK PER INVOCATION**. Complete exactly one task from `$AGENT_DIR/tasks.json`, commit it in git, then output the promise tag and stop.

## Overview

You are implementing the project described in `$AGENT_DIR/prd/SUMMARY.md`.

## Environment

You run directly on the operator's host as their user, with the target workspace at `$PROJECT_ROOT`.

- `$PROJECT_ROOT` may hold one project or several git repos (one per service). Commit in the repo that owns the files you changed.
- Treat everything outside `$PROJECT_ROOT` and `/tmp` as read-only, except `$AGENT_DIR/reports/` which is reserved for your completion reports. Never modify other files in `$AGENT_DIR/` (control files): the host orchestrator owns `tasks.json` and `LOG.md`.
- The network is available. Provider credentials come from the operator's agent config.
- You may use a browser and `sudo` when the task genuinely needs them, but do not install global tooling just to satisfy the prompt.
- Docker is optional. If the project has a compose file and `docker` works, use it; otherwise run the project's services natively.

## Service Containers (optional)

If `$PROJECT_ROOT/docker-compose.yml` (or `compose.yml`) exists and Docker is available, run the project's stack with compose. Always pass `-f`:

```bash
docker compose -f "$PROJECT_ROOT/docker-compose.yml" up -d --build
docker compose -f "$PROJECT_ROOT/docker-compose.yml" ps
docker compose -f "$PROJECT_ROOT/docker-compose.yml" logs --tail 100 service-a
docker compose -f "$PROJECT_ROOT/docker-compose.yml" exec -T service-a sh -lc 'command'
docker compose -f "$PROJECT_ROOT/docker-compose.yml" down -v
```

Rules:

- Never pass `-p`: the project name comes from `COMPOSE_PROJECT_NAME` so the host can tear the stack down.
- Do not use bare `docker run` for the project's services. Containers started that way are invisible to cleanup.
- `exec` needs `-T`; there is no TTY.
- Stop the stack before your promise tag: `docker compose -f "$PROJECT_ROOT/docker-compose.yml" down -v`.
- If Docker is unavailable, start the same services with the project's native commands and verify them with `curl`.

## Before Starting

1. Read `$AGENT_DIR/STEERING.md`. Finish any critical item first, in order.
2. Read the last 5 entries in `$AGENT_DIR/logs/LOG.md` so you do not repeat past work.
3. Read the project's own instructions: `README`, `AGENTS.md`, `package.json`, `Makefile`, or the equivalent for this stack.

## Project Commands

Use the commands this project already defines. Find them in `package.json` scripts, the README, or the build config. Do not assume a stack, a test runner, or a port.

- Run the formatter, linter, type checker, and test suite the project defines for the files you touch.
- If a command does not exist, skip it. Do not add a toolchain just to satisfy this prompt.
- If the task needs a running app, start the project's dev or start command in the background and verify it with `curl`. Do not assume port 3000.

## Task Flow

The orchestrator has selected **$CURRENT_TASK_ID: $CURRENT_TASK_TITLE** for this iteration.

Details:
- Description: $CURRENT_TASK_DESCRIPTION
- PRD reference: $CURRENT_TASK_PRD (if set, read this section for full requirements)
- Implementation steps:
$CURRENT_TASK_STEPS
- Acceptance criteria:
$CURRENT_TASK_ACCEPTANCE

Your workflow:
1. If `$CURRENT_TASK_PRD` is set, read that PRD section for complete domain context.
2. Implement the steps and add or update tests that prove the task works.
3. Run the project's checks for the affected files, then the project-wide test suite.
4. All checks must pass. If you broke an unrelated test, fix it before continuing.
5. Commit changes to git with the Conventional Commit format.
6. Write a task report to `$AGENT_DIR/reports/${CURRENT_TASK_ID}.md` documenting what was implemented, files touched, verification steps performed, and any notes for the operator.
7. Output `<promise>${CURRENT_TASK_ID}:DONE</promise>`. If every task in `$AGENT_DIR/tasks.json` now passes, ALSO output `<promise>COMPLETE</promise>`:
   ```
   <promise>${CURRENT_TASK_ID}:DONE</promise>
   ```
8. Stop immediately. Do not read or start the next task.

## Rules

- **ONE task per invocation.** Your response must end at the promise tag. Do not continue after it.
- Kill any background process you started (dev server, watcher) before the promise tag.
- Work only inside `$PROJECT_ROOT`. Do not run `git init`, change remotes, or `git push`.
- Do not commit secrets. Keep `.env` and credentials out of git.
- Do not rewrite unrelated code or reformat files you did not touch.
- If the same fix fails twice, stop and report instead of looping.

## Help Tags

Try to solve the task first. When you are truly stuck, output one tag and stop.

1. **BLOCKED** for environment problems you cannot fix from the host: missing or invalid credentials, a required service that is down, no network, or a tool that is not installed. Output:

```
<promise>BLOCKED:brief description</promise>
```

These are not bugs. Do not retry with alternative downloads or package managers.

2. **DECIDE** for a choice only a human can make: library choice, architecture, unclear requirements, breaking changes. Output:

```
<promise>DECIDE:question (Option A vs B)</promise>
```
