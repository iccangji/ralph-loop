#!/bin/bash
# Task state module for ralph.sh
# Host owns .agent/tasks.json and .agent/logs/LOG.md; the agent cannot write them.
# Dependencies: constants.sh, logging.sh

TASKS_FILE="$SCRIPT_DIR/.agent/tasks.json"

# Strip the TASK- prefix and any leading zeros so "TASK-001", "TASK-1", and "1" match.
bare_task_id() {
  local id="${1#TASK-}"
  # If numeric, strip leading zeros, preserving a lone 0
  if printf '%s' "$id" | grep -Eq '^[0-9]+$'; then
    id=$(printf '%s' "$id" | sed 's/^0*//')
    [ -z "$id" ] && id="0"
  fi
  printf '%s' "$id"
}

# Return success when at least one task exists and every task has status: "completed".
all_tasks_passed() {
  local file="${1:-$TASKS_FILE}"
  jq -e 'length > 0 and all(.status == "completed" or .passes == true)' "$file" >/dev/null 2>&1
}

# Set status: "completed" for one task, append a log entry, and commit both files.
# Usage: mark_task_complete <task-id>
mark_task_complete() {
  local id
  id=$(bare_task_id "$1")
  [ -n "$id" ] || return 0

  local title
  title=$(jq -r --arg id "$id" \
    '.[] | select((.id | tostring | ltrimstr("TASK-")) == $id) | .title' \
    "$TASKS_FILE" 2>/dev/null | head -1)

  local updated
  updated=$(jq --arg id "$id" \
    'map(if (.id | tostring | ltrimstr("TASK-")) == $id then .status = "completed" | del(.passes) else . end)' \
    "$TASKS_FILE" 2>/dev/null) || return 0
  [ -n "$updated" ] || return 0
  printf '%s\n' "$updated" > "$TASKS_FILE"

  mkdir -p "$(dirname "$PROGRESS_FILE")"
  printf '%s\n' "- $(date '+%Y-%m-%d %H:%M') — TASK-${id} ${title}" >> "$PROGRESS_FILE"

  git -C "$SCRIPT_DIR" add "$TASKS_FILE" "$PROGRESS_FILE" >/dev/null 2>&1 || true
  git -C "$SCRIPT_DIR" commit -q -m "chore(agent): mark TASK-${id} done" >/dev/null 2>&1 || true
}

# Mark a task as in_progress (in-memory/on-disk without git commit)
# Usage: set_task_in_progress <task-id>
set_task_in_progress() {
  local id
  id=$(bare_task_id "$1")
  [ -n "$id" ] || return 0

  local updated
  updated=$(jq --arg id "$id" \
    'map(if (.id | tostring | ltrimstr("TASK-") | (if test("^[0-9]+$") then gsub("^0*"; "") | (if length == 0 then "0" else . end) else . end)) == $id then .status = "in_progress" else . end)' \
    "$TASKS_FILE" 2>/dev/null) || return 0
  [ -n "$updated" ] || return 0
  printf '%s\n' "$updated" > "$TASKS_FILE"
}

# Reset a task back to pending (for retry after failed iteration)
# Usage: set_task_pending <task-id>
set_task_pending() {
  local id
  id=$(bare_task_id "$1")
  [ -n "$id" ] || return 0

  local updated
  updated=$(jq --arg id "$id" \
    'map(if (.id | tostring | ltrimstr("TASK-") | (if test("^[0-9]+$") then gsub("^0*"; "") | (if length == 0 then "0" else . end) else . end)) == $id then .status = "pending" else . end)' \
    "$TASKS_FILE" 2>/dev/null) || return 0
  [ -n "$updated" ] || return 0
  printf '%s\n' "$updated" > "$TASKS_FILE"
}

# Reset any orphaned in_progress tasks back to pending (e.g. after crash or interrupt)
# Usage: reset_in_progress
reset_in_progress() {
  [ -f "$TASKS_FILE" ] || return 0
  local updated
  updated=$(jq 'map(if .status == "in_progress" then .status = "pending" else . end)' \
    "$TASKS_FILE" 2>/dev/null) || return 0
  [ -n "$updated" ] || return 0
  printf '%s\n' "$updated" > "$TASKS_FILE"
}