# A Ralph Wiggum Loop implementation that works™

[![@pageai/ralph-loop version](https://img.shields.io/npm/v/@pageai/ralph-loop?label=npm&style=flat)](https://www.npmjs.com/package/@pageai/ralph-loop)

📚 Full docs: [ralphloop.sh](https://ralphloop.sh)

Ralph is a long-running AI agent loop. Ralph automates software development tasks by iteratively working through a task list until completion. This allows for long running agent loops, effectively enabling AI to code for days at a time.

This is an implementation that actually works, containing a hackable script so you can configure it to your env and favorite agentic AI CLI. It runs the [pi coding agent](https://pi.dev) in plain Docker, one ephemeral container per iteration.

#### 👉 [Watch the video](https://www.youtube.com/watch?v=3TL8Ez66I3o) for an in-depth walkthrough.

[![Ralph Wiggum Loop](https://github.com/user-attachments/assets/be94b8ba-b073-489d-b07e-d11db975a907)](https://www.youtube.com/watch?v=3TL8Ez66I3o)

- [Getting Started](#getting-started)
  - [(Optional) Set up code base](#optional-set-up-code-base)
  - [1️⃣ Step 1: Install Ralph](#1️⃣-step-1-install-ralph)
  - [2️⃣ Step 2: Create a PRD + task list](#2️⃣-step-2-create-a-prd--task-list)
  - [3️⃣ Step 3: Install Docker and sign in to pi](#3️⃣-step-3-install-docker-and-sign-in-to-pi)
  - [4️⃣ Step 4: Run Ralph](#4️⃣-step-4-run-ralph)
- [Running the Ralph Loop with custom options](#running-the-ralph-loop-with-custom-options)
  - [(Optional) Adjusting to your language/framework](#optional-adjusting-to-your-languageframework)
- [How It Works](#how-it-works)
- [How Is This Different from Other Ralphs?](#how-is-this-different-from-other-ralphs)
- [Steering the Agent](#steering-the-agent)
- [Support](#support)
  - [Promise Tags](#promise-tags)
  - [Exit Codes](#exit-codes)
- [Structure](#structure)
- [Continued Development](#continued-development)
- [Skills](#skills)
  - [Available Skills](#available-skills)
  - [Skills Directory Structure](#skills-directory-structure)
- [Reference](#reference)
  - [Docker runtime](#docker-runtime)
  - [Vitest configuration](#vitest-configuration)
  - [Agent CLI and flags](#agent-cli-and-flags)
  - [Starting from scratch](#starting-from-scratch)
- [Debugging](#debugging)
  - [How to inspect the container and debug](#how-to-inspect-the-container-and-debug)
  - [Network access and local providers](#network-access-and-local-providers)
  - [Authentication issues](#authentication-issues)
- [License](#license)

---------------------------------

## Getting Started

### (Optional) Set up code base

I recommend using a CLI to bootstrap your project with the necessary tools and dependencies, e.g.:

```bash
# for a Tanstack app:
npx @tanstack/cli create lib --add-ons eslint,form,tanstack-query,nitro --no-git

# or for a Next.js app
npx create-next-app@latest my-app --typescript --tailwind --eslint --app
```

> If you must start from a blank slate, which is not recommended, see [Starting from scratch](#starting-from-scratch). You can also go for a more barebone start by running `npx create-vite@latest src --template react-ts`

### 1️⃣ Step 1: Install Ralph

Run this in your project's directory to install Ralph.

```bash
npx @pageai/ralph-loop
```

> Docs: [ralphloop.sh](https://ralphloop.sh)

### 2️⃣ Step 2: Create a PRD + task list

Use the `prd-creator` skill to generate a PRD from your requirements.<br/>
Open up Claude Code or Cursor etc., **switch to plan mode**, and prompt it with **your requirements**. Like so:

```
Use the prd-creator skill to help me create a PRD and task list for the below requirements.

An app is already set up with React, Tailwind CSS and TypeScript.

Requirements:

- A SaaS product that helps users manage their finances.
- Target audience: Small business owners and freelancers.
- Core features:
  - Track income and expenses.
  - Create and send invoices.
  - Track payments and receipts.
  - Generate reports and insights.
  - Connect to bank accounts and credit cards.
  - Connect to accounting software.
  - Connect to payment processors.
- Use the shadcn/ui library for components.
- Integrate with Stripe for payments.
- Use Supabase for database.
- You can find env variables in the .env.example file: SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, STRIPE_SECRET_KEY, etc. are available in the runtime.

// etc.
```

> Check out [the video](https://www.youtube.com/watch?v=3TL8Ez66I3o&t=403s) for a more realistic example on how to write requirements.

<details>
<summary><strong>✨ Pro tips</strong></summary>

- mention libraries and frameworks you want to use
- mention env variables, e.g. for DB, 3rd party API keys, etc. Store them in `.env` and add it to **.gitignore**
- describe user flows and journeys
- add relevant docs and UI references if applicable inside `/docs` and mention them in the requirements
- be as descriptive as possible
- *it's fine to write in your own language*

</details>
<br/>

Then, follow the Skill's instructions and verify the PRD and then tasks.<br/>
**It is highly recommended that you review individual task requirements before starting the loop. Review EACH TASK INDIVIDUALLY.**

### 3️⃣ Step 3: Install Docker and sign in to pi

Ralph runs pi inside Docker. Install Docker Engine or Docker Desktop and make sure the daemon is running. Ralph builds the pinned pi image (`ralph-pi:1.5.2`) automatically the first time it runs.

Authenticate pi **on the host**. Ralph mounts your pi config into the container, so a login performed on the host is available inside:

```bash
pi
```

Then run `/login` inside the pi TUI and follow the instructions. Credentials and provider settings live in `~/.pi/agent` on the host.

> **Local providers:** `~/.pi/agent/models.json` is copied into the project on every run, with loopback URLs (`localhost` / `127.0.0.1`) rewritten to `host.docker.internal`. The host file is never modified.

> **API keys:** providers configured with an `apiKey` in `models.json` work as-is. Files other than `models.json` and `settings.json` are not exposed to the container, so keep provider credentials in `models.json`.

### 4️⃣ Step 4: Run Ralph

```bash
./ralph.sh -n 50 # Run Ralph Loop with 50 iterations
```

> ✍️ Note: the first run builds the Docker image and may take a few minutes. Later runs reuse the cached image.

## Running the Ralph Loop with custom options

```bash
# Run the agent loop (default: 10 iterations)
./ralph.sh

# Run with custom iteration limit
./ralph.sh 5
./ralph.sh -n 5
./ralph.sh --max-iterations 5

# Run exactly one iteration
./ralph.sh --once

# Select the agent explicitly (pi is the only supported agent)
./ralph.sh --agent pi
./ralph.sh -a pi -n 5

# Pass extra options to pi
./ralph.sh -- --model combo1

# Show help
./ralph.sh --help
```

> NB: you might need to run `chmod +x ralph.sh` to make the script executable.

> The default "mode" is "implementation". Depending on your use case, you might want to change `.agent/PROMPT.md` to a different mode, e.g. "refactor", "review", "test" etc.

⚠️ If you want to use a different language or testing framework, see below.

### (Optional) Adjusting to your language/framework

This script assumes the following are installed **inside the container image**:
- [Vitest](https://vitest.dev/) for unit testing
- [TypeScript](https://www.typescriptlang.org/) for type checking
- [ESLint](https://eslint.org/) for linting
- [Prettier](https://prettier.io/) for formatting

The image contains Node.js, git, ripgrep, jq, curl, Python 3, and build tools. There is no browser, so the loop verifies work with unit tests and `curl` rather than browser automation. Run browser-based end-to-end tests on the host, outside the loop.

If you'd like to use a different language, testing framework etc. please adjust `.agent/PROMPT.md` and `Dockerfile.pi` to reflect your setup, server ports and startup commands etc.

👉 The loop is controlled by this prompt, which will be sent to the agent each iteration.

---------------------------------

## How It Works

Each iteration, Ralph will:
1. Find the highest-priority incomplete task from `.agent/tasks.json`
2. Work through the task steps defined in `.agent/tasks/TASK-{ID}.json`
3. Run tests, linting, and type checking
4. Complete task, update task status and commit changes
5. Repeat until all tasks pass or max iterations reached

## How Is This Different from Other Ralphs?

This was kept hackable so you can make it your own.<br/>
The script follows the original concepts of the Ralph Wiggum Loop, working with fresh contexts and providing clear verifiable feedback.

It also works generically with any task set.

<details>
<summary><strong>✨ Features</strong></summary>

- **PRD generation** - Creates a PRD and task list from requirements
- **Task lookup table generation** - Creates a task lookup table from the PRD
- **Task breakdown + step generation** - Breaks down each task into manageable steps
- **Iteration tracking** - Shows progress through iterations with timing
- **Stream preview** - Shows live output from the Agent
- **Step detection** - Identifies current activity (Thinking, Implementing, Testing, etc.)
- **Notifications** - Alerts when human input is needed
- **History logging** - Saves clean output from each iteration
- **Timing** - Shows timing metrics for each iteration and total time
- **Steering** - Allows prioritizing critical work that needs to be done before the loop can continue
</details>

<br/>
Besides that:

- it allows you to dump unstructured requirements and have the agent create a PRD and task list for you.
- it uses a task lookup table with individual detailed steps → more scalable as you get 100s of tasks done.
- it runs in an isolated Docker container
- it shows progress and stats so you can keep an eye on what's been done
- it instructs the agent to write and run automated tests per task
- it provides observability and traceability of the agent's work, showing a stream of output and capturing full historical logs per iteration

## Steering the Agent

In some cases, you might notice the agent is having trouble, slowed down or struggling to overcome a blocker.

While the loop is running, you can edit the `.agent/STEERING.md` file to add critical work that needs to be done before the loop can continue.

The agent will check this file each iteration and if it finds any critical work, it will skip tasks and complete the critical work first.

## Support

The `ralph.sh` script is designed to be hackable.
It runs the pi coding agent in an ephemeral Docker container, and you can select it explicitly with `--agent pi`.
Each run uses a deterministic container name in the form `ralph-<agent>-<current-dir>-<hash8>`, and the container is removed on exit or double Ctrl+C.

> NB: pi discovers project skills under `.agents/skills`. The container gets `.agent/skills` bind-mounted to that path, so the canonical source stays in `.agent/skills`.

### Promise Tags

Ralph uses semantic tags to communicate status:
- `<promise>COMPLETE</promise>` - All tasks finished successfully
- `<promise>BLOCKED:reason</promise>` - Agent needs human help
- `<promise>DECIDE:question</promise>` - Agent needs a decision

### Exit Codes

| Code | Meaning                          |
| ---- | -------------------------------- |
| 0    | COMPLETE - All tasks finished    |
| 1    | MAX_ITERATIONS - Reached limit   |
| 2    | BLOCKED - Needs human help       |
| 3    | DECIDE - Needs human decision    |
| 4    | DOCKER_ERROR - Docker unavailable |
| 5    | AUTH_ERROR - Agent not signed in |
| 6    | PROVIDER_ERROR - Provider unreachable |

## Structure

```
.agent/
├── PROMPT.md           # Prompt sent to Agent each iteration
├── tasks.json          # Task lookup table (required)
├── tasks/              # Individual task specs (TASK-{ID}.json)
├── prd/
│   ├── PRD.md          # Product requirements document
│   └── SUMMARY.md      # Short project overview sent to Agent each iteration
├── logs/
│   └── LOG.md          # Progress log (auto-created)
├── history/            # Iteration output logs
├── pi/                 # Generated container models.json (gitignored)
└── skills/             # Shared skills (source of truth)

.pi/
└── mcp.json            # Project MCP servers used by pi

.agents/
└── skills/             # Mount target for .agent/skills (gitignored)
```

## Continued Development

As Ralph implements tasks, you might notice that you want some tweaks, features or even bug fixes.<br/>
To do so, you need to continue using the `prd-creator` skill to update the PRD and task list.

For example:

```
I would like to expand the PRD. Use the prd-creator skill to create these tasks:

- there is a bug in X that should be fixed by doing Y
- create a new feature that implement Z

etc.
```

It's fine to add multiple tasks at once.

## Skills

Skills are reusable agent capabilities that provide specialized knowledge and workflows. The canonical source is `.agent/skills/`. Pi discovers project skills under `.agents/skills`, so the container bind-mounts `.agent/skills` there.

### Available Skills

| Skill                         | Description                                             |
| ----------------------------- | ------------------------------------------------------- |
| `component-refactoring`       | Patterns for splitting and refactoring React components |
| `e2e-tester`                  | End-to-end testing workflows                            |
| `frontend-code-review`        | Code quality and performance review guidelines          |
| `frontend-testing`            | Unit and integration testing patterns                   |
| `mysql`                       | MySQL/InnoDB schema, indexing, query tuning, and ops    |
| `postgres`                    | PostgreSQL best practices and query optimization        |
| `prd-creator`                 | Create PRDs and task breakdowns for Ralph               |
| `skill-creator`               | Create new skills                                       |
| `vercel-react-best-practices` | React/Next.js performance patterns                      |
| `vitest-best-practices`       | Vitest structure, assertions, mocks, async tests, and performance |
| `web-design-guidelines`       | UI/UX design principles                                 |

### Skills Directory Structure

`.agent/skills/` is the only copy of the skills. Nothing is symlinked: Ralph mounts that directory at `.agents/skills` inside the container, which is where pi looks for project skills.

```
 # Source of truth (host)
.agent/skills/
    ├── component-refactoring/
    ├── e2e-tester/
    ├── postgres/
    ├── ...

# Mount target inside the container (empty on the host, gitignored)
.agents/skills/  -> bind mount of .agent/skills
```

## Reference

### Docker runtime

Ralph runs each iteration in a plain Docker container. The image is built from `Dockerfile.pi` and pinned to a specific pi version:

```bash
# Rebuild the image after changing Dockerfile.pi
docker build --build-arg PI_VERSION=1.5.2 -t ralph-pi:1.5.2 -f Dockerfile.pi .

# Run a shell inside the image for debugging
docker run --rm -it --entrypoint bash ralph-pi:1.5.2
```

Per iteration Ralph:

- runs the container as your host UID/GID (`--user "$(id -u):$(id -g)"`),
- mounts the project at the same absolute path as on the host,
- mounts `.agent/pi/models.json`, `~/.pi/agent/settings.json`, `.agent/skills`, and `~/.gitconfig` read-only,
- uses bridge networking with `host.docker.internal` mapped to the host gateway,
- removes the container when the iteration ends or Ralph exits.

### Vitest configuration

If you are using Vitest, here is a recommended configuration:

```typescript:vitest.config.ts
import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import path from "path";

export default defineConfig({
  plugins: [react()],
  test: {
    environment: "node",
    globals: true,
    include: ["lib/**/*.test.ts", "lib/**/*.test.tsx"],
    // setupFiles: ['./vitest.setup.ts'], // Include this if using Next.js
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname),
    },
  },
});

```

If you are using Next.js, you'll also need a `vitest.setup.ts` file to mock the `next/image` and `next/link` components.

```typescript:vitest.setup.ts
import '@testing-library/jest-dom/vitest'
import { vi } from 'vitest'
import React from 'react'

// If using Next.js, mock next/image
vi.mock('next/image', () => ({
  default: ({ src, alt, ...props }: { src: string; alt: string }) => {
    return React.createElement('img', { src, alt, ...props })
  },
}))

// If using Next.js, mock next/link
vi.mock('next/link', () => ({
  default: ({
    children,
    href,
    ...props
  }: {
    children: React.ReactNode
    href: string
  }) => {
    return React.createElement('a', { href, ...props }, children)
  },
}))
```

### Agent CLI and flags

Ralph currently supports one agent: `pi` ([`@earendil-works/pi-coding-agent`](https://www.npmjs.com/package/@earendil-works/pi-coding-agent)). The `--agent` flag is kept so the interface stays stable:

```bash
./ralph.sh --agent pi   # default and only supported value
./ralph.sh -a pi
```

You can pass extra options to pi after Ralph's `--` separator. They are appended to the pi command inside the container:

```bash
./ralph.sh -- --model combo1
./ralph.sh -- --provider 9Router --model combo1
```

The pi version is pinned by `PI_VERSION` in `scripts/lib/constants.sh` and `ARG PI_VERSION` in `Dockerfile.pi`. Update both to upgrade, then rebuild the image.

### Starting from scratch

For AI to actually verify its implementation and for the loop to work, you need a way to verify it.

To that end, at the minimum you'll need a unit test framework. Browser-based end-to-end tests are run on the host, outside the loop, because the container has no browser.

For example, you can use the following commands to install Vitest:

```bash
npm i vitest jsdom typescript eslint prettier -D

# If using React, also recommend installing:
npm i @vitejs/plugin-react @testing-library/dom @testing-library/jest-dom @testing-library/react @testing-library/user-event -D
```

It is recommended that you add skills for your specific language and framework. See [skills.sh](https://skills.sh) to discover existing skills.

## Debugging

### How to inspect the container and debug

Containers are ephemeral and removed when Ralph exits, so there is no long-lived sandbox to attach to. To debug, reproduce the exact `docker run` command Ralph uses. Ralph prints the container name when it starts and the full command is visible in `.agent/history/`.

The command has this shape:

```bash
docker run --rm -it \
  --name ralph-pi-debug \
  --add-host host.docker.internal:host-gateway \
  --user "$(id -u):$(id -g)" \
  -e HOME=/home/pi \
  -e PI_CODING_AGENT_DIR=/pi-agent \
  -w "$PWD" \
  -v "$PWD:$PWD" \
  -v "$PWD/.agent/pi/models.json:/pi-agent/models.json:ro" \
  -v "$HOME/.pi/agent/settings.json:/pi-agent/settings.json:ro" \
  -v "$PWD/.agent/skills:$PWD/.agents/skills:ro" \
  -v "$HOME/.gitconfig:/home/pi/.gitconfig:ro" \
  --entrypoint bash \
  ralph-pi:1.5.2
```

Inside that shell you can run `pi`, inspect files, and check what the agent sees. The project is mounted at the same absolute path as on the host.

### Network access and local providers

Docker containers have outbound network access by default, so `npm install` and provider calls work without extra policy rules.

A provider running on the host loopback is reachable at `host.docker.internal`. Ralph rewrites `http://localhost:<port>` and `http://127.0.0.1:<port>` in the generated `.agent/pi/models.json` to `http://host.docker.internal:<port>` on every run. The host file is untouched.

At startup Ralph verifies that a loopback provider is reachable from inside the container and exits with code `6` if it is not.

The dev server started by the agent (`npm run dev` at `localhost:3000`) lives inside the container only. It is not published to the host; verify it with `curl` from inside the container.

### Authentication issues

pi reads credentials from its agent directory. Ralph mounts `~/.pi/agent/settings.json` and a generated `models.json` into the container, so:

- providers configured with an `apiKey` in `~/.pi/agent/models.json` work without further setup;
- OAuth sessions stored in `~/.pi/agent/auth.json` are not mounted, so use an `apiKey` for container runs;
- if pi reports `Invalid API key`, sign in again on the host with `pi` → `/login` or fix the provider entry in `models.json`.

Ralph exits with code `5` on authentication errors and prints the host login command.

## License

MIT
