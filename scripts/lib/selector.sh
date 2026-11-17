#!/bin/bash
# Selector module for ralph.sh
# Deterministic task selection via jq
# Dependencies: constants.sh, logging.sh

# Validate task graph: check for cycles and missing deps
# Returns 0 if valid, 1 if error (logs error)
# Usage: validate_task_graph <tasks.json>
validate_task_graph() {
  local tasks_file="$1"
  local lib_dir="${SCRIPT_DIR:-.}/scripts/lib"

  # Check for circular dependencies using Kahn's algorithm
  local cycle_check
  cycle_check=$(jq -rf "$lib_dir/cycle_check.jq" "$tasks_file" 2>/dev/null)
  if [ "$cycle_check" = "CYCLE" ]; then
    log_error "Circular dependency detected in tasks.json"
    return 1
  fi

  # Check for missing dependency references
  local missing_check
  missing_check=$(jq -rf "$lib_dir/missing_check.jq" "$tasks_file" 2>/dev/null)
  if [ "$missing_check" = "MISSING" ]; then
    log_error "Missing dependency reference in tasks.json"
    return 1
  fi

  return 0
}

# Select the next runnable task from tasks.json
# Returns task ID on stdout, or empty string if none runnable
# Exits with 1 on error, 0 on success (even if no task)
# Usage: select_next_task <tasks.json> <tasks_dir>
select_next_task() {
  local tasks_file="$1"
  local tasks_dir="$2"

  [ -f "$tasks_file" ] || { log_error "tasks.json not found: $tasks_file"; return 1; }
  [ -d "$tasks_dir" ] || { log_error "tasks dir not found: $tasks_dir"; return 1; }

  # Validate graph first
  validate_task_graph "$tasks_file" || return 1

  # Find the highest-priority runnable task
  # Runnable: passes=false AND all depends_on have passes=true
  local next_id
  next_id=$(jq -r '
    # First, build a lookup of which tasks have passes=true
    . as $tasks
    | ($tasks | map({(.id): .passes}) | add) as $passed
    # Filter runnable tasks
    | map(select(.passes == false
        and ( (.depends_on // []) | all( $passed[.] == true ) )
    ))
    # Sort by priority asc, then by original array order (stable)
    | sort_by(.priority)
    | .[0].id // empty
  ' "$tasks_file" 2>/dev/null)

  if [ -z "$next_id" ]; then
    return 0  # no runnable task (all done or blocked)
  fi

  # Validate the task spec file exists
  local spec_file="$tasks_dir/TASK-${next_id#TASK-}.json"
  if [ ! -f "$spec_file" ]; then
    log_error "Spec file missing for $next_id: $spec_file"
    return 1
  fi

  printf "%s" "$next_id"
}

# Get the full task spec JSON for a given task ID
# Usage: get_task_spec <tasks_dir> <task_id>
get_task_spec() {
  local tasks_dir="$1"
  local task_id="$2"

  local spec_file="$tasks_dir/TASK-${task_id#TASK-}.json"
  [ -f "$spec_file" ] || { log_error "Spec file missing: $spec_file"; return 1; }

  cat "$spec_file"
}