> ⛔ **ONE TASK PER INVOCATION**. Complete exactly one task from `$AGENT_DIR/tasks.json`, commit it in git, then output the promise tag and stop.

## Overview

You are implementing the project described in `$AGENT_DIR/prd/SUMMARY.md`.

## Environment

You run inside an ephemeral Docker container as the host user, with the target workspace mounted at `$PROJECT_ROOT` — the same absolute path it has on the host.

- Only `$PROJECT_ROOT` is writable. `$AGENT_DIR/` (control files) and `~/.agents/skills` are mounted **READ-ONLY**.
- **DO NOT attempt to modify `$AGENT_DIR/tasks.json` or `$AGENT_DIR/logs/LOG.md`**. The host orchestrator manages task state and logs automatically based on your promise tags.
- There is no browser and no display. Verify work with the project's tests and `curl`.
- There is no `sudo`, and you cannot install system packages. Use the tools already in the image and project-level package managers.
- Network access is available. A provider running on the host is reachable at `host.docker.internal`.
- You control the host Docker daemon through the mounted socket. `docker` and `docker compose` are installed.

## Service Containers

The workspace is mounted at its real host path, so a compose file at
`$PROJECT_ROOT/docker-compose.yml` with relative bind mounts such as
`./service-a:/app` resolves correctly. Always pass `-f`:

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

Tasks are listed in `$AGENT_DIR/tasks.json`.

1. Pick the highest-priority task where `passes: false` and all prerequisites in `depends_on` (if present) already have `passes: true`.
2. Read its full spec in `$AGENT_DIR/tasks/TASK-${ID}.json`.
3. Implement the steps and add or update tests that prove the task works.
4. Run the project's checks for the affected files, then the project-wide test suite.
5. All checks must pass. If you broke an unrelated test, fix it before continuing.
6. Commit changes to git with the Conventional Commit format.
7. Output `<promise>TASK-{ID}:DONE</promise>`. If every task in `$AGENT_DIR/tasks.json` now passes (including the one you just completed), ALSO output `<promise>COMPLETE</promise>`. Output BOTH tags:
   ```
   <promise>TASK-001:DONE</promise>
   <promise>COMPLETE</promise>
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

1. **BLOCKED** for environment problems you cannot fix from inside the container: missing or invalid credentials, a required service that is down, no network, or a tool the image does not contain. Output:

```
<promise>BLOCKED:brief description</promise>
```

These are not bugs. Do not retry with alternative downloads or package managers.

2. **DECIDE** for a choice only a human can make: library choice, architecture, unclear requirements, breaking changes. Output:

```
<promise>DECIDE:question (Option A vs B)</promise>
```
