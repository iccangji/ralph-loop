#!/bin/bash
# Agent module for ralph.sh
# opencode CLI only, per-run state, command construction
# Dependencies: constants.sh, logging.sh
#
# The agent runs directly on the host with the repo root as its working
# directory, so each run gets a temporary session database. Nothing in the
# operator's home is written by the loop.

SUPPORTED_AGENTS="opencode"
DEFAULT_AGENT="opencode"

# Primary agent the loop drives. It launches the researcher, coder, and
# reviewer subagents; see .opencode/agents/.
RALPH_FACTORY_AGENT="factory-lead"

AGENT_STATE_DIR=""
SKILLS_LINK_CREATED=false

supported_agents_list() {
  echo "$SUPPORTED_AGENTS"
}

normalize_agent_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

is_supported_agent() {
  [ "$1" = "opencode" ]
}

agent_display_name() {
  case "$1" in
    opencode) echo "OpenCode" ;;
    *) echo "$1" ;;
  esac
}

# Minimum version the agent CLI must report. Kept in constants.sh so the
# preflight and the docs cannot drift apart.
agent_min_version() {
  case "$1" in
    opencode) echo "$MIN_OPENCODE_VERSION" ;;
    *) echo "" ;;
  esac
}

# Installed version of the agent CLI, semver only.
# Usage: version=$(agent_version opencode)
agent_version() {
  "$1" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

# True when version $1 is at least $2. Compares three numeric parts without
# relying on GNU sort -V, so it also works on BSD/macOS.
# Usage: if version_at_least "$have" "$need"; then ...
version_at_least() {
  local have="$1"
  local need="$2"
  [ -n "$have" ] || return 1

  local IFS=.
  local -a have_parts
  local -a need_parts
  read -r -a have_parts <<< "$have"
  read -r -a need_parts <<< "$need"

  local i
  local have_part
  local need_part
  for i in 0 1 2; do
    have_part=$((10#${have_parts[$i]:-0}))
    need_part=$((10#${need_parts[$i]:-0}))
    if [ "$have_part" -gt "$need_part" ]; then
      return 0
    fi
    if [ "$have_part" -lt "$need_part" ]; then
      return 1
    fi
  done
  return 0
}

path_hash() {
  local project_path="$1"
  if command -v shasum >/dev/null 2>&1; then
    printf "%s" "$project_path" | shasum -a 256 | awk '{print substr($1, 1, 8)}'
  elif command -v sha256sum >/dev/null 2>&1; then
    printf "%s" "$project_path" | sha256sum | awk '{print substr($1, 1, 8)}'
  else
    printf "%s" "$project_path" | cksum | awk '{printf "%08x", $1}'
  fi
}

# Per-run state: a throwaway session database for one Ralph run.
prepare_agent_state() {
  AGENT_STATE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ralph-${RALPH_AGENT}-XXXXXX") || {
    log_error "Could not create agent state directory"
    exit $EXIT_RUNTIME_ERROR
  }
}

cleanup_agent_state() {
  if [ -n "$AGENT_STATE_DIR" ] && [ -d "$AGENT_STATE_DIR" ]; then
    rm -rf "$AGENT_STATE_DIR"
  fi
  AGENT_STATE_DIR=""
}

# opencode discovers project skills from .opencode/skills under its cwd, and
# the agent's cwd is the repo root. The link is created only when absent and
# is gitignored, so a run cannot commit it.
prepare_project_skills() {
  local skills="$SCRIPT_DIR/.agents/skills"
  [ -d "$skills" ] || return 0

  mkdir -p "$SCRIPT_DIR/.opencode" || return 0

  if [ -e "$SCRIPT_DIR/.opencode/skills" ] || [ -L "$SCRIPT_DIR/.opencode/skills" ]; then
    return 0
  fi

  if ! ln -s "$skills" "$SCRIPT_DIR/.opencode/skills"; then
    return 0
  fi

  SKILLS_LINK_CREATED=true
}

cleanup_project_skills() {
  [ "$SKILLS_LINK_CREATED" = true ] || return 0

  rm -f "$SCRIPT_DIR/.opencode/skills" 2>/dev/null || true
  SKILLS_LINK_CREATED=false
}

format_agent_extra_args() {
  local output=""
  local arg
  local quoted
  for arg in "${AGENT_EXTRA_ARGS[@]}"; do
    printf -v quoted "%q" "$arg"
    output="$output $quoted"
  done
  printf "%s" "$output"
}

# Build the shell-quoted command for one agent invocation.
# Usage: build_agent_command
build_agent_command() {
  local extra_args
  extra_args=$(format_agent_extra_args)

  case "$RALPH_AGENT" in
    opencode) build_opencode_command "$extra_args" ;;
  esac
}

# opencode: a private server and a throwaway session DB keep the operator's
# session store out of the loop. --agent pins the primary agent to the factory
# lead so interactive use of the repo keeps its own default.
build_opencode_command() {
  local extra_args="$1"

  printf 'env OPENCODE_DB=%q %q run --format json --auto --standalone --agent %q' \
    "$AGENT_STATE_DIR/opencode.db" "opencode" "$RALPH_FACTORY_AGENT"
  if [ -n "$extra_args" ]; then
    printf ' %s' "$extra_args"
  fi
  printf ' %q' "$PROMPT_CONTENT"
}
