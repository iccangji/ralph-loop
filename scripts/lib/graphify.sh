#!/bin/bash
# Workspace graph module for ralph.sh
# Refreshes the graphify knowledge graph on the host after the agent reports a
# completed task. The graph is derived data, so a failure never stops the loop.
# Dependencies: constants.sh, logging.sh

GRAPHIFY_TIMEOUT="${GRAPHIFY_TIMEOUT:-180}"

# Rebuild or incrementally update workspace/graphify-out.
# Usage: update_workspace_graph
update_workspace_graph() {
  local ws="$SCRIPT_DIR/workspace"

  if ! command -v graphify >/dev/null 2>&1; then
    log_warn "graphify not found on PATH; skipping graph update"
    return 0
  fi

  if [ ! -d "$ws" ]; then
    return 0
  fi

  # Keep the derived graph out of the agent's commits without editing tracked
  # files: .git/info/exclude is local to this checkout.
  if [ -d "$ws/.git" ]; then
    mkdir -p "$ws/.git/info"
    grep -qx "graphify-out/" "$ws/.git/info/exclude" 2>/dev/null \
      || echo "graphify-out/" >> "$ws/.git/info/exclude"
  fi

  log_info "Updating workspace graph..."
  if (cd "$ws" && timeout "$GRAPHIFY_TIMEOUT" graphify update . >/dev/null 2>&1); then
    log_success "Workspace graph updated"
  else
    log_warn "Graph update skipped (graphify failed or timed out)"
  fi
}
