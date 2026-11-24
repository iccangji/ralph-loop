#!/bin/bash
# Notification module for ralph.sh
# Cross-platform sound and desktop notifications
# Dependencies: None

# Play notification sound cross-platform
# Usage: play_notification_sound
# Supports macOS, Linux (PulseAudio), Windows (WSL), with terminal bell fallback
play_notification_sound() {
  (
    # Try macOS first (afplay)
    if command -v afplay &> /dev/null; then
      afplay /System/Library/Sounds/Glass.aiff 2>/dev/null || true
    # Try Linux (PulseAudio)
    elif command -v paplay &> /dev/null; then
      paplay /usr/share/sounds/freedesktop/stereo/complete.oga 2>/dev/null || true
    # Try Windows/WSL (PowerShell)
    elif command -v powershell.exe &> /dev/null; then
      powershell.exe -Command "[System.Media.SystemSounds]::Asterisk.Play()" 2>/dev/null || true
    fi
    # Always try terminal bell as additional notification
    echo -e '\a' 2>/dev/null || true
  ) &
}

# Show desktop notification cross-platform
# Usage: show_notification "title" "message"
# Supports macOS (osascript), Linux (notify-send), fails silently on unsupported platforms
show_notification() {
  local title="$1"
  local message="$2"
  (
    # Try macOS (osascript)
    if command -v osascript &> /dev/null; then
      osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null || true
    # Try Linux (notify-send)
    elif command -v notify-send &> /dev/null; then
      notify-send "$title" "$message" 2>/dev/null || true
    fi
  ) &
}

# Format seconds as a short human string: 0s, 45s, 2m 05s, 1h 02m
# Usage: human_duration <seconds>
human_duration() {
  local total="${1:-0}"
  if [ "$total" -lt 60 ]; then
    echo "${total}s"
  elif [ "$total" -lt 3600 ]; then
    printf '%dm %02ds\n' $((total / 60)) $((total % 60))
  else
    printf '%dh %02dm\n' $((total / 3600)) $(((total % 3600) / 60))
  fi
}

# Build a one-line human-readable summary for a given status
# Usage: build_webhook_message <status> <completed_count> <total_tasks> <iterations> <elapsed>
build_webhook_message() {
  local status="$1"
  local completed="$2"
  local total="$3"
  local iterations="$4"
  local elapsed="$5"
  local duration
  duration=$(human_duration "$elapsed")

  case "$status" in
    complete)
      echo "Ralph completed all tasks: ${completed}/${total} done in ${iterations} iteration(s), ${duration}"
      ;;
    blocked)
      echo "Ralph is BLOCKED: ${completed}/${total} tasks done after ${iterations} iteration(s), ${duration}"
      ;;
    decide)
      echo "Ralph needs a decision: ${completed}/${total} tasks done after ${iterations} iteration(s), ${duration}"
      ;;
    circuit_breaker)
      echo "Ralph tripped the circuit breaker: ${completed}/${total} tasks done after ${iterations} iteration(s), ${duration}"
      ;;
    max_iterations)
      echo "Ralph hit max iterations: ${completed}/${total} tasks done after ${iterations} iteration(s), ${duration}"
      ;;
    auth_error)
      echo "Ralph stopped on an authentication error: ${completed}/${total} tasks done, ${duration}"
      ;;
    provider_error)
      echo "Ralph stopped on a provider error: ${completed}/${total} tasks done, ${duration}"
      ;;
    *)
      echo "Ralph finished with status '${status}': ${completed}/${total} tasks done, ${duration}"
      ;;
  esac
}

# Send webhook notification on workflow completion
# Usage: send_webhook <status> <exit_code> [message]
# Env vars: RALPH_WEBHOOK_URL, RALPH_WEBHOOK_SECRET
# Status: complete, blocked, decide, circuit_breaker, max_iterations, auth_error, provider_error, error
# If message is omitted, a human-readable summary is generated from the status.
send_webhook() {
  local status="$1"
  local exit_code="${2:-0}"
  local custom_message="${3:-}"
  local url="${RALPH_WEBHOOK_URL:-}"
  local secret="${RALPH_WEBHOOK_SECRET:-}"

  [ -n "$url" ] || return 0
  command -v curl >/dev/null 2>&1 || return 0

  local session_id="${SESSION_ID:-$(date +%Y%m%d-%H%M%S)}"
  local elapsed=$(( $(date +%s) - ${START_TIME:-$(date +%s)} ))
  local iterations="${#ITERATION_TIMES[@]}"
  local completed_tasks="${COMPLETED_TASK_IDS:-}"
  local total_tasks completed_count pending_count

  # Count tasks from tasks.json if available
  if [ -f "$SCRIPT_DIR/.agent/tasks.json" ]; then
    total_tasks=$(jq 'length' "$SCRIPT_DIR/.agent/tasks.json" 2>/dev/null || echo 0)
    completed_count=$(jq '[.[] | select(.status == "completed")] | length' "$SCRIPT_DIR/.agent/tasks.json" 2>/dev/null || echo 0)
    pending_count=$(jq '[.[] | select(.status == "pending")] | length' "$SCRIPT_DIR/.agent/tasks.json" 2>/dev/null || echo 0)
  else
    total_tasks=0
    completed_count=0
    pending_count=0
  fi

  local message="$custom_message"
  if [ -z "$message" ]; then
    message=$(build_webhook_message "$status" "$completed_count" "$total_tasks" "$iterations" "$elapsed")
  fi

  local payload
  payload=$(jq -n \
    --arg event "ralph_finished" \
    --arg message "$message" \
    --arg status "$status" \
    --arg exit_code "$exit_code" \
    --arg session_id "$session_id" \
    --arg iterations "$iterations" \
    --arg elapsed "$elapsed" \
    --arg completed_tasks "$completed_tasks" \
    --arg total_tasks "$total_tasks" \
    --arg completed_count "$completed_count" \
    --arg pending_count "$pending_count" \
    --arg log_file "$RUN_LOG_FILE" \
    '{
      event: $event,
      message: $message,
      status: $status,
      exit_code: ($exit_code | tonumber),
      session_id: $session_id,
      iterations: ($iterations | tonumber),
      elapsed_seconds: ($elapsed | tonumber),
      completed_tasks: ($completed_tasks | split(" ") | map(select(length > 0))),
      tasks_summary: {
        total: ($total_tasks | tonumber),
        completed: ($completed_count | tonumber),
        pending: ($pending_count | tonumber)
      },
      log_file: $log_file
    }' 2>/dev/null) || return 0

  local headers=(-H "Content-Type: application/json")
  if [ -n "$secret" ]; then
    if command -v openssl >/dev/null 2>&1; then
      local sig
      sig=$(printf '%s' "$payload" | openssl dgst -sha256 -hmac "$secret" 2>/dev/null | sed 's/^.*= //' | tr -d '\n')
      headers+=(-H "X-Hub-Signature-256: sha256=$sig" -H "X-Signature-256: sha256=$sig")
    fi
  fi

  curl -sS --max-time 10 "${headers[@]}" -d "$payload" "$url" >/dev/null 2>&1 || true
}
