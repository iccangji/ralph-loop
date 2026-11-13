#!/bin/bash
# Task state module for ralph.sh
# Host owns .agent/tasks.json and .agent/logs/LOG.md; the container sees them read-only.
# Dependencies: constants.sh, logging.sh

TASKS_FILE="$SCRIPT_DIR/.agent/tasks.json"

# Strip the TASK- prefix so "TASK-001" and "001" match the same entry.
bare_task_id() {
  printf '%s' "${1#TASK-}"
}

# Return success when at least one task exists and every task has passes: true.
all_tasks_passed() {
  jq -e 'length > 0 and all(.passes == true)' "$TASKS_FILE" >/dev/null 2>&1
}

# Set passes: true for one task, append a log entry, and commit both files.
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
    'map(if (.id | tostring | ltrimstr("TASK-")) == $id then .passes = true else . end)' \
    "$TASKS_FILE" 2>/dev/null) || return 0
  [ -n "$updated" ] || return 0
  printf '%s\n' "$updated" > "$TASKS_FILE"

  mkdir -p "$(dirname "$PROGRESS_FILE")"
  printf '%s\n' "- $(date '+%Y-%m-%d %H:%M') — TASK-${id} ${title}" >> "$PROGRESS_FILE"

  git -C "$SCRIPT_DIR" add "$TASKS_FILE" "$PROGRESS_FILE" >/dev/null 2>&1 || true
  git -C "$SCRIPT_DIR" commit -q -m "chore(agent): mark TASK-${id} done" >/dev/null 2>&1 || true
}