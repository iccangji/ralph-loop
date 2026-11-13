#!/bin/bash
# Preflight module for ralph.sh
# Pre-flight checks before starting the main loop
# Dependencies: constants.sh, logging.sh

# Check if workspace is a git repository
# Usage: check_git_repo
check_git_repo() {
  if [ ! -d "$SCRIPT_DIR/workspace/.git" ]; then
    log_error "workspace directory ($SCRIPT_DIR/workspace) is not a git repository. Run 'git init' inside it first."
    exit 1
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