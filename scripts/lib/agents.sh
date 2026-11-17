#!/bin/bash
# Agent module for ralph.sh
# Supported agent CLIs, per-run state, command construction
# Dependencies: constants.sh, logging.sh
#
# Agents run directly on the host, so each run gets its own temporary state
# directory. Nothing in the operator's home is written by the loop.

SUPPORTED_AGENTS="opencode pi"
DEFAULT_AGENT="opencode"

AGENT_STATE_DIR=""
SKILLS_LINK_CREATED=false

supported_agents_list() {
  echo "$SUPPORTED_AGENTS"
}

normalize_agent_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

is_supported_agent() {
  case "$1" in
    opencode|pi)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

agent_display_name() {
  case "$1" in
    opencode) echo "OpenCode" ;;
    pi) echo "Pi" ;;
    *) echo "$1" ;;
  esac
}

agent_login_command() {
  echo "$1"
}

# Minimum version the agent CLI must report. Kept in constants.sh so the
# preflight and the docs cannot drift apart.
agent_min_version() {
  case "$1" in
    opencode) echo "$MIN_OPENCODE_VERSION" ;;
    pi) echo "$MIN_PI_VERSION" ;;
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

# Per-run state: config copies and session storage for one Ralph run.
prepare_agent_state() {
  AGENT_STATE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ralph-${RALPH_AGENT}-XXXXXX") || {
    log_error "Could not create agent state directory"
    exit $EXIT_RUNTIME_ERROR
  }

  case "$RALPH_AGENT" in
    pi) prepare_pi_state ;;
  esac
}

# pi reads models and trust from its agent dir, never from the project .pi/.
# Copy the project config in and trust only the workspace.
prepare_pi_state() {
  local agent_dir="$AGENT_STATE_DIR/pi"
  mkdir -p "$agent_dir"

  if [ -d "$SCRIPT_DIR/.pi" ]; then
    cp -R "$SCRIPT_DIR/.pi/." "$agent_dir/" 2>/dev/null || true
  fi

  printf '{"%s":true}\n' "$SCRIPT_DIR/workspace" > "$agent_dir/trust.json"
}

cleanup_agent_state() {
  if [ -n "$AGENT_STATE_DIR" ] && [ -d "$AGENT_STATE_DIR" ]; then
    rm -rf "$AGENT_STATE_DIR"
  fi
  AGENT_STATE_DIR=""
}

# opencode discovers project skills from .opencode/skills under its cwd. The
# workspace is the cwd, so link the canonical repo skills in for the run.
# The directory is created only when absent and marked ignored, so an agent
# running `git add -A` cannot commit the per-run link into the project repo.
prepare_workspace_skills() {
  [ "$RALPH_AGENT" = "opencode" ] || return 0

  local ws="$SCRIPT_DIR/workspace"
  local skills="$SCRIPT_DIR/.agents/skills"
  [ -d "$ws" ] && [ -d "$skills" ] || return 0

  if [ -e "$ws/.opencode" ] || [ -L "$ws/.opencode" ]; then
    return 0
  fi

  mkdir -p "$ws/.opencode" || return 0
  printf '*\n' > "$ws/.opencode/.gitignore" || true

  if ! ln -s "$skills" "$ws/.opencode/skills"; then
    rm -f "$ws/.opencode/.gitignore" 2>/dev/null || true
    rmdir "$ws/.opencode" 2>/dev/null || true
    return 0
  fi

  SKILLS_LINK_CREATED=true
}

cleanup_workspace_skills() {
  [ "$SKILLS_LINK_CREATED" = true ] || return 0

  local ws="$SCRIPT_DIR/workspace"
  rm -f "$ws/.opencode/skills" "$ws/.opencode/.gitignore" 2>/dev/null || true
  rmdir "$ws/.opencode" 2>/dev/null || true
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
    pi) build_pi_command "$extra_args" ;;
  esac
}

# opencode: a private server and a throwaway session DB keep the operator's
# 470 MB session store out of the loop.
build_opencode_command() {
  local extra_args="$1"

  printf 'env OPENCODE_DB=%q %q run --format json --auto --standalone' \
    "$AGENT_STATE_DIR/opencode.db" "opencode"
  if [ -n "$extra_args" ]; then
    printf ' %s' "$extra_args"
  fi
  printf ' %q' "$PROMPT_CONTENT"
}

build_pi_command() {
  local extra_args="$1"

  printf 'env PI_CODING_AGENT_DIR=%q %q --mode json --approve --no-session' \
    "$AGENT_STATE_DIR/pi" "pi"
  if [ -d "$SCRIPT_DIR/.agents/skills" ]; then
    printf ' --skill %q' "$SCRIPT_DIR/.agents/skills"
  fi
  if [ -n "$extra_args" ]; then
    printf ' %s' "$extra_args"
  fi
  printf ' -p %q' "$PROMPT_CONTENT"
}
