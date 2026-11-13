# Ralph Wiggum Loop

Ralph runs an AI coding agent inside an ephemeral Docker container in an autonomous loop to implement specs task by task.

## Architecture

- **Host (Orchestrator)**: Runs `ralph.sh`. Owns `.agent/tasks.json` and `.agent/logs/LOG.md`. Manages iterations, tracks task completion via promise tags, and marks tasks as completed upon verification.
- **Container (Worker)**: Runs `pi` in an ephemeral Docker container.
  - Mounts `workspace/` as **Read-Write** (all code and git commits happen here).
  - Mounts `.agent/` and `.agents/` as **Read-Only** (specs, tasks, PRD, and skills cannot be altered by the agent).
  - Mounts `.pi/` as **Read-Only** (model configuration and settings).
  - Network is bridged to host via `host.docker.internal`.

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
├── workspace/              # Target project repository (mounted :rw at /workspace)
└── scripts/
    └── lib/                # Runner modules
```

## Quickstart

1. Configure models and provider in `.pi/models.json` (pointing to `http://host.docker.internal:<port>/v1`).
2. Initialize target project in `workspace/`:
   ```bash
   cd workspace && git init
   ```
3. Define tasks in `.agent/tasks.json` and `.agent/tasks/TASK-{ID}.json`.
4. Run Ralph:
   ```bash
   ./ralph.sh --once
   ```

## Options

- `--once`: Run a single iteration and stop.
- `--max-iterations N`: Maximum number of iterations before stopping (default: 10).
- `--help`: Display usage and options.
