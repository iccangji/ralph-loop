#!/bin/bash
# Ralph Wiggum - Long-running AI agent loop
# Usage: ./ralph.sh [--help] [--once] [--max-iterations N] [N]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PRD_FILE="$SCRIPT_DIR/.agent/prd/PRD.md"
PROGRESS_FILE="$SCRIPT_DIR/.agent/logs/LOG.md"
HISTORY_DIR="$SCRIPT_DIR/.agent/history"
RUN_LOG_FILE="$SCRIPT_DIR/.agent/logs/ralph-$(date +%Y%m%d-%H%M%S).log"

# Auto-tee all output to run log and persistent ralph.log (disabled via RALPH_NO_LOG=1)
if [ "${RALPH_NO_LOG:-0}" != "1" ]; then
  mkdir -p "$(dirname "$RUN_LOG_FILE")"
  exec > >(tee -a "$SCRIPT_DIR/.agent/logs/ralph.log" "$RUN_LOG_FILE") 2>&1
fi

source "$SCRIPT_DIR/scripts/lib/constants.sh"
source "$SCRIPT_DIR/scripts/lib/logging.sh"
source "$SCRIPT_DIR/scripts/lib/stack.sh"
source "$SCRIPT_DIR/scripts/lib/preflight.sh"
source "$SCRIPT_DIR/scripts/lib/timing.sh"
source "$SCRIPT_DIR/scripts/lib/terminal.sh"
source "$SCRIPT_DIR/scripts/lib/spinner.sh"
source "$SCRIPT_DIR/scripts/lib/preview.sh"
source "$SCRIPT_DIR/scripts/lib/output.sh"
source "$SCRIPT_DIR/scripts/lib/cleanup.sh"
source "$SCRIPT_DIR/scripts/lib/promise.sh"
source "$SCRIPT_DIR/scripts/lib/tasks.sh"
source "$SCRIPT_DIR/scripts/lib/graphify.sh"
source "$SCRIPT_DIR/scripts/lib/notify.sh"
source "$SCRIPT_DIR/scripts/lib/checkpoint.sh"
source "$SCRIPT_DIR/scripts/lib/factory.sh"
source "$SCRIPT_DIR/scripts/lib/selector.sh"
source "$SCRIPT_DIR/scripts/lib/agents.sh"
source "$SCRIPT_DIR/scripts/lib/display.sh"
source "$SCRIPT_DIR/scripts/lib/args.sh"

# Timing
START_TIME=$(date +%s)
ITERATION_TIMES=()
TOTAL_ITERATION_TIME=0
PREV_ITERATION_TIME=0

# Circuit breaker: track consecutive iterations without task completion
CONSECUTIVE_FAILURES=0

# Session ID for unique history file naming (YYYYMMDD-HHMMSS format). This is used to prevent overwrites between runs.
SESSION_ID=$(date +%Y%m%d-%H%M%S)

# Temporary files for spinner communication
STEP_FILE=$(mktemp)
PREVIEW_LINE_FILE=$(mktemp)

# Background process tracking for cleanup
AGENT_PID=""
OUTPUT_FILE=""
FULL_OUTPUT_FILE=""

# Set up traps
trap cleanup EXIT
trap handle_interrupt INT

# Parse arguments (sets MAX_ITERATIONS, ONCE_FLAG, RALPH_AGENT, AGENT_EXTRA_ARGS)
parse_arguments "$@"
RALPH_AGENT_NAME=$(agent_display_name "$RALPH_AGENT")

# Single-instance lock: only one Ralph may run per checkout. flock is released
# by the kernel on exit or crash, so a hard kill never leaves a stale lock.
LOCK_FILE="$SCRIPT_DIR/.agent/.ralph.lock"
mkdir -p "$(dirname "$LOCK_FILE")"
if command -v flock >/dev/null 2>&1; then
  exec 200>>"$LOCK_FILE"
  if ! flock -n 200; then
    HOLDER_PID=$(cat "$LOCK_FILE" 2>/dev/null || true)
    echo -e "${RD}❌ Another Ralph instance is already running${R}${HOLDER_PID:+ (PID: $HOLDER_PID)}" >&2
    exit 1
  fi
  echo "$$" > "$LOCK_FILE"
else
  echo "⚠️  flock not found; single-instance lock disabled" >&2
fi

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  mkdir -p "$(dirname "$PROGRESS_FILE")"
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

# Pre-flight checks
check_git_repo
check_required_files
check_history_dir
check_ansi_support
check_agent
check_opencode_config
check_factory_agents
check_factory_script
check_prd_slugs
check_provider_reachable
check_stack_capability

# Per-run agent state (config copies, sessions) and the workspace skill link.
prepare_agent_state
prepare_project_skills

# Reset any orphaned in_progress tasks from previous crash/interrupt
reset_in_progress

# A crashed run leaves worktrees and branches behind; no task can be live yet.
factory_cleanup_orphans
factory_warn_multiple_prds

FACTORY_SCRIPT="$SCRIPT_DIR/scripts/factory-git.sh"

# Stable compose project name for this checkout. The agent inherits it, so
# down_project_stack can find the containers it started.
export COMPOSE_PROJECT_NAME
COMPOSE_PROJECT_NAME=$(compose_project_name)

# Early exit if all tasks already passed
if all_tasks_passed; then
  log_success "All tasks already complete. Nothing to do."
  factory_finish_completed_prds "$AUTO_PUBLISH" "$AUTO_PUSH_ONLY"
  send_webhook "complete" $EXIT_COMPLETE
  exit $EXIT_COMPLETE
fi

show_ralph
echo -e " ${C}Starting Ralph${R} ・ ${Y}v$VERSION${R} ・ Agent: ${Y}$RALPH_AGENT_NAME${R} ・ Max iterations: ${Y}$MAX_ITERATIONS${R}"
echo ""

for i in $(seq 1 $MAX_ITERATIONS); do
  ITERATION_START=$(date +%s)

  # Initialize step timing for this iteration
  init_iteration_step_times

  echo -e "${B}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
  echo -e "  ↪ ${R}Iteration ${Y}$i${R} of ${Y}$MAX_ITERATIONS${R}"
  echo -e "${B}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
  echo -e ""

  # Select next runnable task (shell-side deterministic selection)
  TASK_ID=$(select_next_task "$SCRIPT_DIR/.agent/tasks.json" "$SCRIPT_DIR/.agent/tasks")
  if [ -z "$TASK_ID" ]; then
    log_success "No runnable tasks remaining."
    factory_finish_completed_prds "$AUTO_PUBLISH" "$AUTO_PUSH_ONLY"
    send_webhook "complete" $EXIT_COMPLETE
    exit $EXIT_COMPLETE
  fi

  # Load the task spec and inject into prompt
  TASK_SPEC=$(get_task_spec "$SCRIPT_DIR/.agent/tasks" "$TASK_ID")
  TASK_TITLE=$(echo "$TASK_SPEC" | jq -r '.title')
  TASK_DESCRIPTION=$(echo "$TASK_SPEC" | jq -r '.description')
  TASK_STEPS=$(echo "$TASK_SPEC" | jq -r '.steps[]? // empty')
  TASK_ACCEPTANCE=$(echo "$TASK_SPEC" | jq -r '.acceptance_criteria[]? // empty')
  TASK_PRD=$(echo "$TASK_SPEC" | jq -r '.prd // empty')
  TASK_VERIFY=$(echo "$TASK_SPEC" | jq -c '.verify // []')

  echo -e "${C}  → Selected task: ${Y}$TASK_ID${R} - ${Y}$TASK_TITLE${R}"

  # Mark task as in_progress (crash recovery)
  set_task_in_progress "$TASK_ID"

  # Run Agent with the ralph prompt + selected task spec. PROJECT_ROOT is the workspace path on the
  # host: the agent runs there directly, so relative paths and git commits land
  # in the service repos. AGENT_DIR points at the control files, which live
  # next to the workspace, not inside it.
  PROMPT_CONTENT="PROJECT_ROOT=$SCRIPT_DIR/workspace
AGENT_DIR=$SCRIPT_DIR/.agent
FACTORY_SCRIPT=$FACTORY_SCRIPT
CURRENT_TASK_ID=$TASK_ID
CURRENT_TASK_TITLE=$TASK_TITLE
CURRENT_TASK_DESCRIPTION=$TASK_DESCRIPTION
CURRENT_TASK_PRD=$TASK_PRD
CURRENT_TASK_VERIFY=$TASK_VERIFY
CURRENT_TASK_STEPS=$(printf '%s\n' "$TASK_STEPS" | sed 's/^/  /')
CURRENT_TASK_ACCEPTANCE=$(printf '%s\n' "$TASK_ACCEPTANCE" | sed 's/^/  /')

$(cat $SCRIPT_DIR/.agent/PROMPT.md)"

  # Capture git checkpoint before agent runs
  checkpoint_workspace

  # Start spinner
  start_spinner

  # Initialize rolling preview
  init_rolling_preview

  # Run Agent and capture output while updating spinner and preview
  OUTPUT_FILE=$(mktemp)
  FULL_OUTPUT_FILE=$(mktemp)

  # Run the agent directly on the host. Output is JSONL on stdout; stderr is
  # captured too so provider and permission warnings reach the transcript.
  export PROMPT_CONTENT

  AGENT_COMMAND=$(build_agent_command)
  run_agent_command "$OUTPUT_FILE" "$AGENT_COMMAND" &
  AGENT_PID=$!

  # Track position in output file for incremental reading
  LAST_POS=0

  # Monitor output and update spinner step and rolling preview
  while kill -0 "$AGENT_PID" 2>/dev/null; do
    if [ -f "$OUTPUT_FILE" ]; then
      # Only consume complete lines: a partially written JSON record would be
      # parsed as a fragment and its text lost.
      SAFE_SIZE=$(last_complete_line_offset "$OUTPUT_FILE" "$LAST_POS")

      # Read new complete lines
      if [ "$SAFE_SIZE" -gt "$LAST_POS" ]; then
        while IFS= read -r line; do
          if [ -n "$line" ]; then
            # Parse JSON and extract text content
            parsed=$(parse_json_content "$line")
            if [ -n "$parsed" ]; then
              # Save to full output
              echo "$parsed" >> "$FULL_OUTPUT_FILE"
              # Update spinner step
              update_spinner_step "$parsed"
              # Update preview line under spinner
              update_preview_line "$parsed"
            fi
          fi
        done < <(tail -c +$((LAST_POS + 1)) "$OUTPUT_FILE" 2>/dev/null | head -c $((SAFE_SIZE - LAST_POS)))
        LAST_POS=$SAFE_SIZE
      fi
    fi
    sleep 0.2 || true
  done

  wait "$AGENT_PID" || true
  AGENT_PID=""  # Clear PID after process exits

  # Process any remaining output
  if [ -f "$OUTPUT_FILE" ]; then
    CURRENT_SIZE=$(stat -f%z "$OUTPUT_FILE" 2>/dev/null || stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$CURRENT_SIZE" -gt "$LAST_POS" ]; then
      while IFS= read -r line; do
        if [ -n "$line" ]; then
          parsed=$(parse_json_content "$line")
          if [ -n "$parsed" ]; then
            echo "$parsed" >> "$FULL_OUTPUT_FILE"
          fi
        fi
      done < <(tail -c +$((LAST_POS + 1)) "$OUTPUT_FILE" 2>/dev/null)
    fi
  fi

  OUTPUT=$(cat "$FULL_OUTPUT_FILE" 2>/dev/null || cat "$OUTPUT_FILE")

  # Surface provider and authentication failures early. opencode emits a
  # {"type":"error"} event instead of a plain error line.
  PROVIDER_ERROR_MESSAGE=""
  if [ -f "$OUTPUT_FILE" ] && command -v jq &>/dev/null; then
    PROVIDER_ERROR_MESSAGE=$(jq -R 'fromjson? // empty' "$OUTPUT_FILE" 2>/dev/null \
      | jq -rs '[ .[] | select(.type == "error") | .error.message ] | last // ""' 2>/dev/null)
  fi

  if [ -n "$PROVIDER_ERROR_MESSAGE" ] || echo "$OUTPUT" | grep -qi "Invalid API key"; then
    stop_spinner
    clear_rolling_preview
    echo ""
    echo -e "${RD}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
    echo -e "  ❌ ${RD}Agent Error${R}"
    echo -e "${RD}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
    if [ -n "$PROVIDER_ERROR_MESSAGE" ]; then
      echo -e "  $PROVIDER_ERROR_MESSAGE"
    else
      echo -e "  Invalid API key or unreachable provider."
    fi
    rm -f "$OUTPUT_FILE" "$FULL_OUTPUT_FILE"
    RALPH_HOST=1 "$FACTORY_SCRIPT" abort "$TASK_ID" >/dev/null 2>&1 || true
    if echo "$PROVIDER_ERROR_MESSAGE $OUTPUT" \
      | grep -qiE 'api key|auth|unauthorized|forbidden|401|403'; then
      send_webhook "auth_error" $EXIT_AUTH_ERROR
      exit $EXIT_AUTH_ERROR
    fi
    send_webhook "provider_error" $EXIT_PROVIDER_ERROR
    exit $EXIT_PROVIDER_ERROR
  fi

  # Save cleaned output to history file (SESSION_ID prevents overwrites between runs)
  # Strip ANSI control characters for clean, readable history
  HISTORY_FILE="$HISTORY_DIR/ITERATION-${SESSION_ID}-${i}.txt"
  strip_ansi_file "$OUTPUT_FILE" "$HISTORY_FILE"

  # Extract final summary before removing files
  FINAL_SUMMARY=$(extract_final_summary "$OUTPUT_FILE")

  # Tag detection reads the raw transcript too, so a tag is never missed when
  # the preview stream and the final summary disagree.
  TAG_OUTPUT=$(printf '%s\n%s\n%s' "$OUTPUT" "$FINAL_SUMMARY" "$(cat "$HISTORY_FILE" 2>/dev/null)")

  rm -f "$FULL_OUTPUT_FILE"
  FULL_OUTPUT_FILE=""  # Clear after removal

  # Stop spinner
  stop_spinner

  # Finalize step timing for this iteration (record time spent in last step)
  record_step_time ""

  # Clear rolling preview area to make room for summary
  clear_rolling_preview

  # Display the final summary (persists after iteration)
  if [ -n "$FINAL_SUMMARY" ]; then
    display_final_summary "$FINAL_SUMMARY" 10
  else
    # Fallback: show last 10 lines of parsed output if no result found
    FALLBACK_SUMMARY=$(echo "$OUTPUT" | tail -n 10)
    if [ -n "$FALLBACK_SUMMARY" ]; then
      display_final_summary "$FALLBACK_SUMMARY" 10
    fi
  fi

  # Clean up the raw output file (history file already saved)
  rm -f "$OUTPUT_FILE"
  OUTPUT_FILE=""  # Clear after removal

  # Calculate iteration duration
  ITERATION_END=$(date +%s)
  ITERATION_DURATION=$((ITERATION_END - ITERATION_START))
  ITERATION_TIMES+=($ITERATION_DURATION)
  TOTAL_ITERATION_TIME=$((TOTAL_ITERATION_TIME + ITERATION_DURATION))
  ITERATION_AVG=$((TOTAL_ITERATION_TIME / ${#ITERATION_TIMES[@]}))
  ITERATION_STR=$(format_duration $ITERATION_DURATION)
  AVG_STR=$(format_duration $ITERATION_AVG)
  DELTA_STR=$(format_delta $ITERATION_DURATION $PREV_ITERATION_TIME)
  PREV_ITERATION_TIME=$ITERATION_DURATION

  # Host updates .agent/tasks.json and LOG.md whenever completed task tags appear.
  # A DONE tag is only the agent's claim; the reviewer's verdict is the evidence.
  # Nothing is marked complete until the task branch lands on the PRD branch.
  COMPLETED_TAG_IDS=$(extract_completed_task_ids "$TAG_OUTPUT")

  # The reviewer's verdict is the evidence; the DONE tag is only the lead's
  # claim. A lead that narrates the tag instead of emitting it must not strand
  # a real PASS. merge still re-checks every SHA, so a stale verdict fails.
  VERDICT_FILE=$(factory_verdict_path "$TASK_ID")
  if [ -z "$COMPLETED_TAG_IDS" ] && [ -f "$VERDICT_FILE" ] \
     && jq -e '.verdict == "PASS"' "$VERDICT_FILE" >/dev/null 2>&1; then
    log_warn "No DONE tag for $TASK_ID, but a PASS verdict exists; merging on the verdict."
    COMPLETED_TAG_IDS="$TASK_ID"
  fi

  MERGE_FAILED=0
  MERGED_TAG_IDS=""
  for task_id in $COMPLETED_TAG_IDS; do
    if RALPH_HOST=1 "$FACTORY_SCRIPT" merge "$task_id"; then
      MERGED_TAG_IDS="$MERGED_TAG_IDS $task_id"
    else
      MERGE_FAILED=1
      log_error "Task $task_id could not be merged; discarding its worktree."
      RALPH_HOST=1 "$FACTORY_SCRIPT" abort "$task_id" >/dev/null 2>&1 || true
    fi
  done
  COMPLETED_TAG_IDS=$(printf '%s\n' $MERGED_TAG_IDS)

  for task_id in $COMPLETED_TAG_IDS; do
    mark_task_complete "$task_id"
  done

  COMPLETED_TASK_IDS=$(format_completed_task_ids "$TAG_OUTPUT")
  TASK_IDS_SEGMENT=""
  if [ -n "$COMPLETED_TASK_IDS" ]; then
    TASK_IDS_SEGMENT=" ${C}│${R} Tasks: ${Y}$COMPLETED_TASK_IDS${R}"
  fi

  # Refresh the host-side graph so the next iteration reads a current report
  if [ -n "$COMPLETED_TASK_IDS" ] || has_complete_tag "$TAG_OUTPUT"; then
    update_workspace_graph
  fi

  # Service containers the agent started are siblings, not children of the
  # loop, so they outlive it until the project stack is torn down.
  down_project_stack

  # Check for completion signal
  if [ "$MERGE_FAILED" = 0 ] && { has_complete_tag "$TAG_OUTPUT" || all_tasks_passed; }; then
    ELAPSED=$(($(date +%s) - START_TIME))
    ELAPSED_STR=$(format_duration $ELAPSED)
    echo ""
    echo -e "${GR}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
    echo -e "  🎉 ${GR}Ralph completed all tasks!${R}"
    echo -e "  ✅ Finished at iteration ${GR}$i${R} of ${GR}$MAX_ITERATIONS${R}"
    if [ -n "$DELTA_STR" ]; then
      echo -e "  ⏱️  Iteration $i: ${Y}$ITERATION_STR${R} ($DELTA_STR) ${C}│${R} Average: ${Y}$AVG_STR${R}$TASK_IDS_SEGMENT"
    else
      echo -e "  ⏱️  Iteration $i: ${Y}$ITERATION_STR${R} ${C}│${R} Average: ${Y}$AVG_STR${R}$TASK_IDS_SEGMENT"
    fi
    echo -e "  ⏱️  Total time: ${Y}$ELAPSED_STR${R}"
    display_session_step_totals
    echo -e "${GR}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
    factory_finish_completed_prds "$AUTO_PUBLISH" "$AUTO_PUSH_ONLY"
    send_webhook "complete" $EXIT_COMPLETE
    exit $EXIT_COMPLETE
  fi

  # Check for BLOCKED tag - agent needs human help
  if has_blocked_tag "$TAG_OUTPUT"; then
    BLOCKED_REASON=$(extract_blocked_reason "$TAG_OUTPUT")
    RALPH_HOST=1 "$FACTORY_SCRIPT" abort "$TASK_ID" >/dev/null 2>&1 || true
    ELAPSED=$(($(date +%s) - START_TIME))
    ELAPSED_STR=$(format_duration $ELAPSED)
    play_notification_sound
    show_notification "Ralph - BLOCKED" "$BLOCKED_REASON"
    display_blocked_message "$BLOCKED_REASON" "$i"
    if [ -n "$DELTA_STR" ]; then
      echo -e "  ⏱️  Iteration $i: ${Y}$ITERATION_STR${R} ($DELTA_STR) ${C}│${R} Average: ${Y}$AVG_STR${R}$TASK_IDS_SEGMENT"
    else
      echo -e "  ⏱️  Iteration $i: ${Y}$ITERATION_STR${R} ${C}│${R} Average: ${Y}$AVG_STR${R}$TASK_IDS_SEGMENT"
    fi
    echo -e "  ⏱️  Total time: ${Y}$ELAPSED_STR${R}"
    display_session_step_totals
    send_webhook "blocked" $EXIT_BLOCKED "Ralph is BLOCKED on ${TASK_ID}: ${BLOCKED_REASON}"
    exit $EXIT_BLOCKED
  fi

  # Check for DECIDE tag - agent needs human decision
  if has_decide_tag "$TAG_OUTPUT"; then
    DECIDE_QUESTION=$(extract_decide_question "$TAG_OUTPUT")
    RALPH_HOST=1 "$FACTORY_SCRIPT" abort "$TASK_ID" >/dev/null 2>&1 || true
    ELAPSED=$(($(date +%s) - START_TIME))
    ELAPSED_STR=$(format_duration $ELAPSED)
    play_notification_sound
    show_notification "Ralph - Decision Needed" "$DECIDE_QUESTION"
    display_decide_message "$DECIDE_QUESTION" "$i"
    if [ -n "$DELTA_STR" ]; then
      echo -e "  ⏱️  Iteration $i: ${Y}$ITERATION_STR${R} ($DELTA_STR) ${C}│${R} Average: ${Y}$AVG_STR${R}$TASK_IDS_SEGMENT"
    else
      echo -e "  ⏱️  Iteration $i: ${Y}$ITERATION_STR${R} ${C}│${R} Average: ${Y}$AVG_STR${R}$TASK_IDS_SEGMENT"
    fi
    echo -e "  ⏱️  Total time: ${Y}$ELAPSED_STR${R}"
    display_session_step_totals
    send_webhook "decide" $EXIT_DECIDE "Ralph needs a decision on ${TASK_ID}: ${DECIDE_QUESTION}"
    exit $EXIT_DECIDE
  fi

  # Rollback / Circuit Breaker logic
  # Check if any task was completed this iteration. A failed merge counts as a
  # failed iteration even when another task in the same run did land.
  if { [ -z "$COMPLETED_TASK_IDS" ] && ! has_complete_tag "$TAG_OUTPUT"; } || [ "$MERGE_FAILED" = 1 ]; then
    CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
    RALPH_HOST=1 "$FACTORY_SCRIPT" abort "$TASK_ID" >/dev/null 2>&1 || true
    echo -e "${RD}  ⚠️  Iteration $i completed without completing a task${R} (failures: $CONSECUTIVE_FAILURES/${MAX_RETRIES})"

    if [ "$NO_ROLLBACK" != true ]; then
      rollback_workspace
    else
      log_warn "Rollback disabled (--no-rollback), keeping workspace state"
    fi

    if [ "$MAX_RETRIES" -gt 0 ] && [ "$CONSECUTIVE_FAILURES" -ge "$MAX_RETRIES" ]; then
      echo ""
      echo -e "${RD}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
      echo -e "  🚨 ${RD}Circuit Breaker Tripped${R}: $MAX_RETRIES consecutive failures without progress"
      echo -e "  Check ${Y}.agent/history/ITERATION-${SESSION_ID}-${i}.txt${R} for details"
      echo -e "  Add guidance to ${Y}.agent/STEERING.md${R} if needed"
      echo -e "${RD}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
      send_webhook "circuit_breaker" $EXIT_CIRCUIT_BREAKER
      exit $EXIT_CIRCUIT_BREAKER
    fi
  else
    CONSECUTIVE_FAILURES=0
  fi

  # Calculate elapsed time
  ELAPSED=$(($(date +%s) - START_TIME))
  ELAPSED_STR=$(format_duration $ELAPSED)

  if [ -n "$DELTA_STR" ]; then
    echo -e "${G}  └── ✓ Iteration $i complete${R}$TASK_IDS_SEGMENT ${C}│${R} Iteration: ${Y}$ITERATION_STR${R} ($DELTA_STR) ${C}│${R} Average: ${Y}$AVG_STR${R} ${C}│${R} Total: ${Y}$ELAPSED_STR${R}"
  else
    echo -e "${G}  └── ✓ Iteration $i complete${R}$TASK_IDS_SEGMENT ${C}│${R} Iteration: ${Y}$ITERATION_STR${R} ${C}│${R} Average: ${Y}$AVG_STR${R} ${C}│${R} Total: ${Y}$ELAPSED_STR${R}"
  fi

  # Display per-iteration step times
  STEP_TIMES_OUTPUT=$(format_step_times "ITERATION")
  if [ -n "$STEP_TIMES_OUTPUT" ]; then
    echo -e "${G}      └──${R} $STEP_TIMES_OUTPUT"
  fi
  sleep 2 || true
done

# Calculate final elapsed time
ELAPSED=$(($(date +%s) - START_TIME))
ELAPSED_STR=$(format_duration $ELAPSED)

# Calculate final average (if any iterations completed)
if [ ${#ITERATION_TIMES[@]} -gt 0 ]; then
  FINAL_AVG=$((TOTAL_ITERATION_TIME / ${#ITERATION_TIMES[@]}))
  FINAL_AVG_STR=$(format_duration $FINAL_AVG)
fi

echo ""
echo -e "${Y}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
echo -e "  ⚠️  Ralph reached max iterations${R} (${M}$MAX_ITERATIONS${R})"
if [ ${#ITERATION_TIMES[@]} -gt 0 ]; then
  echo -e "  ⏱️  Average iteration time: ${Y}$FINAL_AVG_STR${R}"
fi
echo -e "  ⏱️  Total time: ${Y}$ELAPSED_STR${R}"
display_session_step_totals
echo -e "  📋 Check progress: ${G}$PROGRESS_FILE${R}"
echo -e "${Y}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
send_webhook "max_iterations" $EXIT_MAX_ITERATIONS
exit $EXIT_MAX_ITERATIONS