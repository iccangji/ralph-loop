#!/bin/bash
# Checkpoint module for ralph.sh
# Git checkpoint and rollback for workspace repositories
# Dependencies: constants.sh, logging.sh

# Discover all git repositories under workspace/
# Returns paths (one per line) of git repo roots
find_workspace_git_repos() {
  local ws="$SCRIPT_DIR/workspace"

  if [ -d "$ws/.git" ]; then
    printf "%s\n" "$ws"
    return
  fi

  find "$ws" -maxdepth 3 -name .git -type d 2>/dev/null | while IFS= read -r gitdir; do
    dirname "$gitdir"
  done
}

# Capture git state for all workspace repos
# Populates global arrays: CHECKPOINT_REPO_PATHS, CHECKPOINT_HEADS, CHECKPOINT_CLEAN
# Usage: checkpoint_workspace
checkpoint_workspace() {
  CHECKPOINT_REPO_PATHS=()
  CHECKPOINT_HEADS=()
  CHECKPOINT_CLEAN=()

  local repo
  local head
  local status

  while IFS= read -r repo; do
    [ -n "$repo" ] || continue
    head=$(git -C "$repo" rev-parse HEAD 2>/dev/null || echo "NO_COMMIT")
    status=$(git -C "$repo" status --porcelain 2>/dev/null || echo "ERROR")

    CHECKPOINT_REPO_PATHS+=("$repo")
    CHECKPOINT_HEADS+=("$head")
    CHECKPOINT_CLEAN+=("$status")

    log_info "Checkpoint: $repo @ $head $( [ -z "$status" ] && echo "(clean)" || echo "(dirty)" )"
  done < <(find_workspace_git_repos)

  # Export for subshells
  export CHECKPOINT_REPO_PATHS CHECKPOINT_HEADS CHECKPOINT_CLEAN
}

# Rollback all workspace repos to their checkpoints
# Usage: rollback_workspace
rollback_workspace() {
  local count=${#CHECKPOINT_REPO_PATHS[@]}
  [ "$count" -gt 0 ] || return 0

  local i
  local repo
  local head

  log_warn "Rolling back $count workspace repository/ies to checkpoint..."

  for i in "${!CHECKPOINT_REPO_PATHS[@]}"; do
    repo="${CHECKPOINT_REPO_PATHS[$i]}"
    head="${CHECKPOINT_HEADS[$i]}"

    if [ "$head" = "NO_COMMIT" ]; then
      # No commits yet — remove all tracked files, reset to empty tree
      log_warn "$repo: no commits, cleaning working tree"
      git -C "$repo" clean -fd 2>/dev/null || true
      git -C "$repo" reset --hard 2>/dev/null || true
    else
      log_warn "$repo: resetting to $head"
      git -C "$repo" reset --hard "$head" 2>/dev/null || true
      git -C "$repo" clean -fd 2>/dev/null || true
    fi

    log_success "Rolled back $repo"
  done

  # Clear arrays
  CHECKPOINT_REPO_PATHS=()
  CHECKPOINT_HEADS=()
  CHECKPOINT_CLEAN=()
}

# Check if all workspace repos were clean at checkpoint
# Returns 0 if all clean, 1 if any dirty
checkpoint_was_clean() {
  local status
  for status in "${CHECKPOINT_CLEAN[@]}"; do
    [ -z "$status" ] || return 1
  done
  return 0
}