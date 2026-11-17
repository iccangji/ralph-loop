#!/bin/bash
# Cleanup module for ralph.sh
# Signal handlers and process cleanup
# Dependencies: constants.sh, agents.sh, stack.sh

CLEANUP_DONE=0

# Terminate a process and all of its descendants. The agent runs on the host,
# so the dev servers it spawned are grandchildren and must die too.
# Usage: kill_process_tree <pid> [signal]
kill_process_tree() {
  local pid="$1"
  local signal="${2:-TERM}"
  local child

  for child in $(pgrep -P "$pid" 2>/dev/null); do
    kill_process_tree "$child" "$signal"
  done

  kill -"$signal" "$pid" 2>/dev/null || true
}

cleanup() {
  if [ "$CLEANUP_DONE" = "1" ]; then
    return 0
  fi
  CLEANUP_DONE=1

  if [ -n "$SPINNER_PID" ] && kill -0 "$SPINNER_PID" 2>/dev/null; then
    kill "$SPINNER_PID" 2>/dev/null || true
    wait "$SPINNER_PID" 2>/dev/null || true
  fi
  SPINNER_PID=""

  if [ -n "$AGENT_PID" ] && kill -0 "$AGENT_PID" 2>/dev/null; then
    kill_process_tree "$AGENT_PID" TERM
    wait "$AGENT_PID" 2>/dev/null || true
  fi
  AGENT_PID=""

  cleanup_workspace_skills
  cleanup_agent_state

  # Containers the agent started are not removed with --rm; drop the stack too.
  if command -v docker &>/dev/null; then
    down_project_stack || true
  fi

  [[ -n "$STEP_FILE" ]] && rm -f "$STEP_FILE" 2>/dev/null || true
  [[ -n "$PREVIEW_LINE_FILE" ]] && rm -f "$PREVIEW_LINE_FILE" 2>/dev/null || true
  [[ -n "$OUTPUT_FILE" ]] && rm -f "$OUTPUT_FILE" 2>/dev/null || true
  [[ -n "$FULL_OUTPUT_FILE" ]] && rm -f "$FULL_OUTPUT_FILE" 2>/dev/null || true
}

LAST_INTERRUPT=0

handle_interrupt() {
  local current_time=$(date +%s)
  local time_diff=$((current_time - LAST_INTERRUPT))

  if [ $time_diff -lt 3 ]; then
    echo ""
    echo -e "${Y}Exiting...${R}"
    exit 130
  else
    LAST_INTERRUPT=$current_time
    echo ""
    echo -e "${Y}⚠️  Press CTRL+C again within 3 seconds to exit${R}"
  fi
}
