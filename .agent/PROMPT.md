> ⛔ **ONE TASK PER INVOCATION**. Complete exactly one task from `.agent/tasks.json`, commit it, then stop.

## Overview

You are implementing the project described in `.agent/prd/SUMMARY.md`.

## Environment

You run inside an ephemeral Docker container as the host user, with the project mounted at the same absolute path as on the host.

- Only the project directory persists between iterations. Anything written under `$HOME` is lost when this iteration ends.
- There is no browser and no display. Verify work with the project's tests and `curl`.
- There is no `sudo`, and you cannot install system packages. Use the tools already in the image and project-level package managers.
- A dev server listens inside the container only. The host cannot reach its port.
- Network access is available. A provider running on the host is reachable at `host.docker.internal`.

## Before Starting

1. Read `.agent/STEERING.md`. Finish any critical item first, in order, and remove it when done.
2. Read the last 5 entries in `.agent/logs/LOG.md` so you do not repeat past work.
3. Read the project's own instructions: `README`, `AGENTS.md`, `package.json`, `Makefile`, or the equivalent for this stack.

## Project Commands

Use the commands this project already defines. Find them in `package.json` scripts, the README, or the build config. Do not assume a stack, a test runner, or a port.

- Run the formatter, linter, type checker, and test suite the project defines for the files you touch.
- If a command does not exist, skip it. Do not add a toolchain just to satisfy this prompt.
- If the task needs a running app, start the project's dev or start command in the background and verify it with `curl`. Do not assume port 3000.

## Task Flow

Tasks are listed in `.agent/tasks.json`.

1. Pick the highest-priority task with `passes: false`.
2. Read its full spec in `.agent/tasks/TASK-${ID}.json`.
3. Implement the steps and add or update tests that prove the task works.
4. Run the project's checks for the affected files, then the project-wide test suite.
5. All checks must pass. If you broke an unrelated test, fix it before continuing.
6. Set `passes: true` for this task in `tasks.json`.
7. Add an entry to `.agent/logs/LOG.md` with the date and a short summary, newest at the top.
8. Commit with the Conventional Commit format.
9. If every task now has `passes: true`, output `<promise>COMPLETE</promise>`. Otherwise output `<promise>TASK-{ID}:DONE</promise>`.
10. Stop immediately. Do not read or start the next task.

## Rules

- **ONE task per invocation.** Your response must end at the promise tag. Do not continue after it.
- Kill any background process you started (dev server, watcher) before the promise tag.
- Work only inside the project directory. Do not run `git init`, change remotes, or `git push`.
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
