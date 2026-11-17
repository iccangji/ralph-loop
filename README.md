# Ralph Wiggum Loop

Ralph runs an AI coding agent CLI directly on the host in an autonomous loop to implement specs task by task.

## Architecture

- **Host (Orchestrator)**: Runs `ralph.sh`. Owns `.agent/tasks.json` and `.agent/logs/LOG.md`. Manages iterations, tracks task completion via promise tags, and marks tasks as completed upon verification.
- **Agent (Worker)**: `opencode` (default) or `pi`, running on the host as your user.
  - `cwd` is `workspace/`, so the agent sees the same absolute paths you do.
  - Each iteration gets a temporary state directory (`mktemp -d`), deleted on exit: a throwaway `OPENCODE_DB` for opencode, a copied `.pi/` plus generated `trust.json` for pi.
  - opencode reads the tracked `opencode.jsonc` from the repo root: model pin plus permission rules (workspace-only edits, no `git push`, no `rm -rf` outside `/tmp`).
  - The repo skills in `.agents/skills` are exposed to the agent (opencode via a per-run `.opencode/skills` symlink, pi via `--skill`).
  - Nothing in your home directory is written by the loop.

> **Boundary:** the workspace-only rule is enforced by opencode permission rules, not by a sandbox. `pi` follows the prompt. Run Ralph on a host and account you control.

## Directory Layout

```
.
├── .agents/
│   └── skills/             # Shared skills (source of truth)
├── .agent/
│   ├── skills/             # Symlink -> ../.agents/skills
│   ├── PROMPT.md           # Project-agnostic agent instructions
│   ├── STEERING.md         # Critical steering instructions
│   ├── tasks.json          # Master task list (host-owned)
│   ├── tasks/              # Detailed task specs TASK-{ID}.json
│   ├── prd/                # PRD.md and SUMMARY.md
│   ├── logs/
│   │   └── LOG.md          # Progress log (host-managed)
│   └── history/            # Raw iteration transcripts
├── .pi/
│   ├── models.json         # Pi models config (gitignored)
│   ├── settings.json       # Pi settings (defaultProvider, defaultModel)
│   └── mcp.json            # Project MCP servers
├── opencode.jsonc          # opencode model pin and permission rules
├── workspace/              # Target project
└── scripts/
    └── lib/                # Runner modules
```

## Requirements

- `bash`, `git`, `curl`, `jq`
- One agent CLI on `PATH`, meeting the minimum version:
  - `opencode` >= 1.19.0 (default), provider credentials in `~/.config/opencode/opencode.jsonc`
  - `pi` >= 1.4.0, configured through this repo's `.pi/`
- Docker is **optional**. It is used only when the project has a compose file, to start and tear down the project's service stack. A project without Docker works fine.

## Quickstart

1. Configure the agent:
   - opencode: set the provider and credentials in your global config, and set the model in `opencode.jsonc`.
   - pi: configure models and provider in `.pi/models.json`.
2. Initialize the target project in `workspace/`. A single repo or one repo per service both work:

   ```bash
   cd workspace && git init          # single repo
   # or: git init each service directory
   ```

3. Optional: put a `docker-compose.yml` at the workspace root. The agent starts it, reads service logs, and `exec`s into containers.
4. Define tasks in `.agent/tasks.json` and `.agent/tasks/TASK-{ID}.json`.
5. Run Ralph:

   ```bash
   ./ralph.sh --once          # one iteration with opencode
   ./ralph.sh -a pi --once    # one iteration with pi
   ```

## Options

- `--once`: Run a single iteration and stop.
- `--agent AGENT`, `-a AGENT`: Select `opencode` (default) or `pi`.
- `--max-iterations N`: Maximum number of iterations before stopping (default: 10).
- `--help`: Display usage and options.
- `-- ARGS...`: Extra arguments forwarded to the agent CLI.
