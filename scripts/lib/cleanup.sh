#!/bin/bash
# Cleanup module for ralph.sh
# Signal handlers and process cleanup
# Dependencies: constants.sh

CLEANUP_DONE=0

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
    pkill -TERM -P "$AGENT_PID" 2>/dev/null || true
    kill "$AGENT_PID" 2>/dev/null || true
    wait "$AGENT_PID" 2>/dev/null || true
  fi
  AGENT_PID=""

  if [ -n "$RALPH_CONTAINER_NAME" ] && command -v docker &>/dev/null; then
    echo -e "  ${Y}📦 Removing container ${RALPH_CONTAINER_NAME}...${R}"
    docker rm -f "$RALPH_CONTAINER_NAME" >/dev/null 2>&1 &
    local remove_pid=$!
    ( sleep 5 && kill "$remove_pid" 2>/dev/null ) &>/dev/null &
    local timeout_pid=$!
    if wait "$remove_pid" 2>/dev/null; then
      echo -e "  ${GR}✅ Container removed${R}"
    fi
    kill "$timeout_pid" 2>/dev/null || true
    wait "$timeout_pid" 2>/dev/null || true
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