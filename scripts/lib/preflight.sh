#!/bin/bash
# Preflight module for ralph.sh
# Pre-flight checks before starting the main loop
# Dependencies: constants.sh, logging.sh

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

# The agent manages service containers through the host daemon, so the socket
# must exist and be mountable.
# Usage: check_docker_socket
check_docker_socket() {
  if [ ! -S /var/run/docker.sock ]; then
    log_error "Docker socket not found at /var/run/docker.sock. The agent needs it to manage service containers."
    exit $EXIT_DOCKER_ERROR
  fi
}

# Compose on the host is what tears the agent's stack down between iterations.
# Usage: check_compose_available
check_compose_available() {
  if docker compose version >/dev/null 2>&1; then
    return 0
  fi

  if find_compose_file >/dev/null 2>&1; then
    log_error "docker compose is required to tear down the project stack, but it is not available."
    exit $EXIT_DOCKER_ERROR
  fi

  log_warn "docker compose not found; the agent cannot start or stop service containers."
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

  if [ ! -f "$SCRIPT_DIR/.pi/models.json" ]; then
    log_error "Required file missing: .pi/models.json"
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