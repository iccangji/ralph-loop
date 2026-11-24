#!/bin/bash
# Preflight module for ralph.sh
# Pre-flight checks before starting the main loop
# Dependencies: constants.sh, logging.sh, agents.sh, stack.sh

# Check that the workspace holds at least one git repository. A single repo at
# the workspace root and a multi-repo layout (one repo per service) both pass.
# Usage: check_git_repo
check_git_repo() {
  local ws="$SCRIPT_DIR/workspace"

  if [ -d "$ws/.git" ]; then
    return 0
  fi

  if find "$ws" -maxdepth 2 -name .git -print -quit 2>/dev/null | grep -q .; then
    return 0
  fi

  log_error "workspace ($ws) has no git repository. Run 'git init' in it, or in each service directory."
  exit 1
}

# The agent runs on the host, so the CLI must be installed and recent enough.
# Usage: check_agent
check_agent() {
  if ! command -v jq >/dev/null 2>&1; then
    log_error "jq is required but was not found on PATH."
    exit $EXIT_RUNTIME_ERROR
  fi

  if ! command -v "$RALPH_AGENT" >/dev/null 2>&1; then
    log_error "Agent CLI '$RALPH_AGENT' not found on PATH."
    exit $EXIT_RUNTIME_ERROR
  fi

  local have
  local need
  have=$(agent_version "$RALPH_AGENT")
  need=$(agent_min_version "$RALPH_AGENT")

  if [ -z "$have" ]; then
    log_error "Could not read a version from '$RALPH_AGENT --version'."
    exit $EXIT_RUNTIME_ERROR
  fi

  if ! version_at_least "$have" "$need"; then
    log_error "$RALPH_AGENT $have is too old; Ralph needs >= $need."
    exit $EXIT_RUNTIME_ERROR
  fi
}

# Fail closed when opencode does not load the tracked project config: without
# it the model pin and the permission rules are silently absent.
# Usage: check_opencode_config
check_opencode_config() {
  [ "$RALPH_AGENT" = "opencode" ] || return 0

  local resolved
  if ! resolved=$(cd "$SCRIPT_DIR" && timeout 30 opencode debug config 2>/dev/null); then
    log_error "Could not read opencode config ('opencode debug config' failed)."
    exit $EXIT_RUNTIME_ERROR
  fi

  # Check that the project config is loaded (path matches $SCRIPT_DIR/opencode.jsonc)
  # and that it has model/provider pinned and agents defined
  if ! printf '%s' "$resolved" | jq -e --arg cfg "$SCRIPT_DIR/opencode.jsonc" '
    any(.[]; .path == $cfg and .info.model.providerID != "" and .info.agents != null)
  ' >/dev/null 2>&1; then
    log_error "opencode did not load $SCRIPT_DIR/opencode.jsonc from the repo root."
    log_error "Refusing to run without the model pin and permission rules."
    exit $EXIT_RUNTIME_ERROR
  fi
}

# The whole task chain depends on four project agents resolving from the repo
# root, which is the agent's cwd. Missing definitions are a startup failure, not
# a task failure.
# Usage: check_factory_agents
check_factory_agents() {
  local resolved
  if ! resolved=$(cd "$SCRIPT_DIR" && timeout 30 opencode debug agents 2>/dev/null); then
    log_error "Could not list opencode agents ('opencode debug agents' failed)."
    exit $EXIT_RUNTIME_ERROR
  fi

  local id
  local missing=""
  for id in "$RALPH_FACTORY_AGENT" researcher coder reviewer; do
    if ! printf '%s' "$resolved" | jq -e --arg id "$id" 'any(.[]; .id == $id)' >/dev/null 2>&1; then
      missing="$missing $id"
    fi
  done

  if [ -n "$missing" ]; then
    log_error "Missing agent definition(s):$missing"
    log_error "Expected them in $SCRIPT_DIR/.opencode/agents/."
    exit $EXIT_RUNTIME_ERROR
  fi

  mkdir -p "$SCRIPT_DIR/.agent/reports"
}

# prepare/merge run from this script, so a missing or non-executable copy is a
# startup failure, not a task failure.
# Usage: check_factory_script
check_factory_script() {
  local script="$SCRIPT_DIR/scripts/factory-git.sh"

  if [ ! -f "$script" ]; then
    log_error "Required file missing: scripts/factory-git.sh"
    exit $EXIT_RUNTIME_ERROR
  fi

  if [ ! -x "$script" ]; then
    chmod +x "$script" 2>/dev/null || {
      log_error "scripts/factory-git.sh is not executable."
      exit $EXIT_RUNTIME_ERROR
    }
  fi
}

# A runnable task whose PRD has no slug fails inside prepare with
# EXIT_GIT_SLUG_MISSING. Say so before the loop starts, while it is still a
# one-line fix. Complete tasks are exempt: legacy PRDs must stay runnable-free.
# Usage: check_prd_slugs
check_prd_slugs() {
  local index="$SCRIPT_DIR/.agent/tasks.json"
  [ -f "$index" ] || return 0

  local id prd slug
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    prd=$(task_prd_file "$id" 2>/dev/null) || continue
    [ -f "$prd" ] || continue
    slug=$(frontmatter_value "$prd" slug)
    factory_valid_slug "$slug" && continue
    log_warn "$(basename "$prd") has pending task $id but no valid 'slug'; prepare will refuse it."
  done < <(jq -r '.[] | select(.status == "pending" or .passes == false) | .id' "$index" 2>/dev/null)
}

# Provider base URLs the active agent will talk to, one per line.
provider_base_urls() {
  local config_home="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
  local candidate
  for candidate in "$config_home/opencode.jsonc" "$config_home/opencode.json" \
                   "$SCRIPT_DIR/opencode.jsonc"; do
    [ -f "$candidate" ] || continue
    jq -r '.provider[]?.options.baseURL // empty' "$candidate" 2>/dev/null
  done | awk '!seen[$0]++'
}

# Probe the provider before the loop starts: a slow or dead endpoint is the
# expensive failure mode, and the agent cannot report it until it is stuck.
# Usage: check_provider_reachable
check_provider_reachable() {
  if ! command -v curl >/dev/null 2>&1; then
    log_warn "curl not found; skipping provider reachability check"
    return 0
  fi

  local urls
  urls=$(provider_base_urls)

  if [ -z "$urls" ]; then
    log_warn "No provider base URL found; skipping reachability check"
    return 0
  fi

  local url
  local failed=()
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    log_info "Checking provider reachability ($url)..."
    if ! curl -s -o /dev/null --max-time 5 "${url%/}/models" >/dev/null 2>&1; then
      failed+=("$url")
    fi
  done <<< "$urls"

  if [ ${#failed[@]} -eq 0 ]; then
    return 0
  fi

  log_error "Cannot reach provider: ${failed[*]}"
  log_error "Check the base URL and that the provider is running."
  exit $EXIT_PROVIDER_ERROR
}

# Docker is optional. Warn when the project has a compose file but the host
# cannot use it, so a later failure is not a surprise.
# Usage: check_stack_capability
check_stack_capability() {
  find_compose_file >/dev/null 2>&1 || return 0

  if ! command -v docker >/dev/null 2>&1; then
    log_warn "Project has a compose file but docker is not installed; services must run natively."
    return 0
  fi

  if ! docker compose version >/dev/null 2>&1; then
    log_warn "docker compose is not available; services must run natively."
  fi
}

# Ensure history directory exists for storing iteration logs
# Usage: check_history_dir
check_history_dir() {
  mkdir -p "$HISTORY_DIR"
  if [ ! -d "$HISTORY_DIR" ]; then
    log_error "Failed to create history directory: $HISTORY_DIR"
    exit 1
  fi
}

# Check for required files and exit if missing, warn for optional files
# Usage: check_required_files
check_required_files() {
  local missing_required=false

  if [ ! -f "$SCRIPT_DIR/.agent/tasks.json" ]; then
    log_error "Required file missing: .agent/tasks.json"
    missing_required=true
  fi

  if [ ! -f "$SCRIPT_DIR/.agent/PROMPT.md" ]; then
    log_error "Required file missing: .agent/PROMPT.md"
    missing_required=true
  fi

  if [ ! -f "$SCRIPT_DIR/opencode.jsonc" ]; then
    log_error "Required file missing for opencode: opencode.jsonc"
    missing_required=true
  fi

  if [ "$missing_required" = true ]; then
    log_error "Please create the required files before running Ralph"
    exit 1
  fi

  if [ ! -f "$SCRIPT_DIR/.agent/prd/SUMMARY.md" ]; then
    log_warn "Optional file missing: .agent/prd/SUMMARY.md"
  fi
}
