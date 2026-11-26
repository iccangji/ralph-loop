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
  # Runnable: status == "pending" AND all depends_on have status == "completed"
  # (also accept legacy .passes field for backwards compatibility)
  local next_id
  next_id=$(jq -r '
    # First, build a lookup of which tasks are completed
    . as $tasks
    | ($tasks | map({(.id): (.status == "completed" or .passes == true)}) | add) as $completed
    # Filter runnable tasks
    | map(select(
        (.status == "pending" or .passes == false)
        and ( (.depends_on // []) | all( $completed[.] == true ) )
    ))
    # Sort by priority asc, then by original array order (stable)
    | sort_by(.priority)
    | .[0].id // empty
  ' "$tasks_file" 2>/dev/null)

  if [ -z "$next_id" ]; then
    return 0  # no runnable task (all done or blocked)
  fi

  # Validate the task spec file exists (supports padded/unpadded)
  local spec_file
  spec_file=$(find_task_spec_file "$tasks_dir" "$next_id")
  if [ ! -f "$spec_file" ]; then
    log_error "Spec file missing for $next_id: $spec_file"
    return 1
  fi

  printf "%s" "$next_id"
}

# Resolve task spec file path, handling padded (TASK-003) and unpadded (TASK-3) IDs.
# Usage: find_task_spec_file <tasks_dir> <task_id>
find_task_spec_file() {
  local tasks_dir="$1"
  local id="$2"

  if [ -f "$tasks_dir/$id.json" ]; then
    printf '%s/%s.json' "$tasks_dir" "$id"
    return 0
  fi

  local bare="${id#TASK-}"
  if printf '%s' "$bare" | grep -Eq '^[0-9]+$'; then
    local unpadded
    unpadded=$(printf '%s' "$bare" | sed 's/^0*//')
    [ -z "$unpadded" ] && unpadded="0"
    if [ -f "$tasks_dir/TASK-${unpadded}.json" ]; then
      printf '%s/TASK-%s.json' "$tasks_dir" "$unpadded"
      return 0
    fi

    local padded
    padded=$(printf '%03d' "$unpadded" 2>/dev/null || printf '%s' "$bare")
    if [ -f "$tasks_dir/TASK-${padded}.json" ]; then
      printf '%s/TASK-%s.json' "$tasks_dir" "$padded"
      return 0
    fi
  fi

  printf '%s/TASK-%s.json' "$tasks_dir" "$bare"
}

# Get the full task spec JSON for a given task ID
# Usage: get_task_spec <tasks_dir> <task_id>
get_task_spec() {
  local tasks_dir="$1"
  local task_id="$2"

  local spec_file
  spec_file=$(find_task_spec_file "$tasks_dir" "$task_id")
  [ -f "$spec_file" ] || { log_error "Spec file missing: $spec_file"; return 1; }

  cat "$spec_file"
}