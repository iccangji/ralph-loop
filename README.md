# Ralph Wiggum Loop

Ralph runs an AI coding agent inside an ephemeral Docker container in an autonomous loop to implement specs task by task.

## Architecture

- **Host (Orchestrator)**: Runs `ralph.sh`. Owns `.agent/tasks.json` and `.agent/logs/LOG.md`. Manages iterations, tracks task completion via promise tags, and marks tasks as completed upon verification.
- **Container (Worker)**: Runs `pi` in an ephemeral Docker container.
  - Mounts `workspace/` as **Read-Write**, at the **same absolute path** it has on the host, so compose files with relative bind mounts resolve correctly.
  - Mounts `.agent/` and `.agents/` as **Read-Only** (specs, tasks, PRD, and skills cannot be altered by the agent).
  - Mounts `.pi/` as **Read-Only** (model configuration and settings).
  - Mounts `/var/run/docker.sock`, so the agent can run `docker compose` against the host daemon: start the project stack, read service logs, and `exec` into service containers.
  - Network is bridged to host via `host.docker.internal`.

> **Security:** the Docker socket grants host-root equivalent access. Run Ralph only on a host you can throw away.

## Directory Layout

```
.
├── .agents/
│   └── skills/             # Shared skills (source of truth)
├── .agent/
│   ├── skills/             # Symlink -> ../.agents/skills
│   ├── PROMPT.md           # Project-agnostic agent instructions (mounted :ro)
│   ├── STEERING.md         # Critical steering instructions (mounted :ro)
│   ├── tasks.json          # Master task list (host-owned, mounted :ro)
│   ├── tasks/              # Detailed task specs TASK-{ID}.json (mounted :ro)
│   ├── prd/                # PRD.md and SUMMARY.md (mounted :ro)
│   ├── logs/
│   │   └── LOG.md          # Progress log (host-managed)
│   └── history/            # Raw iteration transcripts
├── .pi/
│   ├── models.json         # Container models config with host.docker.internal (gitignored)
│   ├── settings.json       # Pi settings (defaultProvider, defaultModel)
│   └── mcp.json            # Project MCP servers
├── workspace/              # Target project (mounted :rw at the same absolute host path)
│   └── docker-compose.yml  # Optional: services the agent starts, inspects, and tears down
└── scripts/
    └── lib/                # Runner modules
```

## Quickstart

1. Configure models and provider in `.pi/models.json`.
2. Initialize target project in `workspace/`. A single repo or one repo per service both work:

   ```bash
   cd workspace && git init          # single repo
   # or: git init each service directory
   ```

3. Optional: put a `docker-compose.yml` at the workspace root. The agent starts it, reads service logs, and `exec`s into containers. Relative bind mounts work because the workspace keeps its host path inside the container.
4. Define tasks in `.agent/tasks.json` and `.agent/tasks/TASK-{ID}.json`.
5. Run Ralph:

   ```bash
   ./ralph.sh --once
   ```

## Options

- `--once`: Run a single iteration and stop.
- `--max-iterations N`: Maximum number of iterations before stopping (default: 10).
- `--help`: Display usage and options.
