#!/bin/bash
# Output module for ralph.sh
# JSON parsing and ANSI stripping utilities
# Dependencies: constants.sh, terminal.sh

# Extract readable text from one opencode JSON event.
# opencode emits complete text parts (no deltas) and tool calls under
# part.state.input, so this maps them to the labels detect_step() expects.
# Usage: parse_opencode_json_content "<json line>"
parse_opencode_json_content() {
  local json_line="$1"

  if ! command -v jq &>/dev/null; then
    return 0
  fi

  printf '%s' "$json_line" | jq -r '
    if .type == "text" then
      (.part.text // empty)
    elif .type == "tool_use" then
      (.part.tool // "") as $tool
      | (.part.state.input // {}) as $args
      | if $tool == "bash" or $tool == "shell" then "Bash command=" + ($args.command // "")
        elif $tool == "write" then "Write file_path=" + ($args.path // $args.filePath // "")
        elif $tool == "edit" then "Edit file_path=" + ($args.path // $args.filePath // "")
        elif $tool == "read" then "Read file_path=" + ($args.path // $args.filePath // "")
        elif $tool == "grep" then "Grep pattern=" + ($args.pattern // "")
        elif $tool == "glob" then "Glob pattern=" + ($args.pattern // "")
        elif $tool == "ls" then "LS path=" + ($args.path // "")
        elif $tool == "skill" then "Skill id=" + ($args.id // "")
        else ($tool + " " + ($args | to_entries | map(.key + "=" + (.value | tostring)) | join(" ")))
        end
    else empty end' 2>/dev/null
}

# Parse one line of the opencode JSON stream and extract readable text.
# Non-JSON lines (stderr warnings) still belong in the preview.
parse_json_content() {
  local json_line="$1"
  local text

  text=$(parse_opencode_json_content "$json_line")
  if [ -n "$text" ]; then
    printf '%s\n' "$text"
    return
  fi

  if ! echo "$json_line" | grep -q '^{'; then
    echo "$json_line"
  fi
}

# Strip ANSI escape sequences and control characters from text
# Usage: clean_text=$(strip_ansi "$text")
# Handles:
#   - CSI sequences: ESC[...m (colors), ESC[...H (cursor), ESC[?...h/l (modes)
#   - OSC sequences: ESC]0;...(BEL or ESC\) for window titles
#   - OSC-like sequences without ESC prefix (from script command)
#   - Caret notation for control chars: ^@ through ^_ (from script command)
#   - Other escapes: ESC followed by various characters
#   - Control chars: backspace, BEL, carriage return, etc.
strip_ansi() {
  local input="$1"
  # First use sed to handle ESC sequences (must be done before tr removes ESC)
  # Then use tr to remove remaining raw control characters
  # tr removes: 0x00-0x08 (NUL through BS), 0x0B-0x0C (VT, FF), 0x0E-0x1A (SO through SUB),
  #             0x1C-0x1F (FS through US) - excludes ESC (0x1B) for sed to process
  # sed handles: ESC sequences, OSC-like patterns, caret notation
  # Note: OSC pattern uses ^ anchor but also handles after caret removal via second pass
  echo "$input" | LC_ALL=C sed \
    -e 's/\x1b\[[0-9;?]*[A-Za-z]//g' \
    -e 's/\x1b\][^\x07]*\x07//g' \
    -e 's/\x1b\][^\x1b]*\x1b\\//g' \
    -e 's/\x1b[()][AB012]//g' \
    -e 's/\x1b[>=]//g' \
    -e 's/\x1b.//g' \
    -e 's/\^[][A-Z@\\^_]//g' \
    -e 's/^0;[^]]*]//g' \
    -e 's/<u0;//g' 2>/dev/null \
    | LC_ALL=C tr -d '\000-\010\013\014\016-\032\034-\037' 2>/dev/null \
    | LC_ALL=C sed -e 's/^0;[^]]*]//g' 2>/dev/null
}

# Strip ANSI from a file and write to output file
# Usage: strip_ansi_file "$input_file" "$output_file"
# First sed processes ESC sequences, then tr removes remaining control characters
strip_ansi_file() {
  local input_file="$1"
  local output_file="$2"
  # First sed processes ESC sequences (before tr removes anything)
  # Then tr removes remaining control characters (excluding newline 0x0A, CR 0x0D)
  # tr range excludes ESC (0x1B = octal 033) which sed already handled
  # Final sed pass cleans up OSC patterns that were hidden by control chars
  LC_ALL=C sed \
    -e 's/\x1b\[[0-9;?]*[A-Za-z]//g' \
    -e 's/\x1b\][^\x07]*\x07//g' \
    -e 's/\x1b\][^\x1b]*\x1b\\//g' \
    -e 's/\x1b[()][AB012]//g' \
    -e 's/\x1b[>=]//g' \
    -e 's/\x1b.//g' \
    -e 's/\^[][A-Z@\\^_]//g' \
    -e 's/^0;[^]]*]//g' \
    -e 's/<u0;//g' \
    "$input_file" 2>/dev/null | LC_ALL=C tr -d '\000-\010\013\014\016-\032\034-\037' 2>/dev/null \
    | LC_ALL=C sed -e 's/^0;[^]]*]//g' 2>/dev/null \
    > "$output_file"
}

# Byte size of a file, portable across GNU and BSD stat.
# Usage: size=$(file_size "$file")
file_size() {
  stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null || echo 0
}

# Byte offset of the end of the last complete line in a file, at or after
# <offset>. A trailing line without a newline is still being written and is
# excluded so a JSON record is never parsed half-finished.
# Usage: safe=$(last_complete_line_offset "$file" "$offset")
last_complete_line_offset() {
  local file="$1"
  local offset="${2:-0}"
  local size
  size=$(file_size "$file")

  if [ "$size" -le "$offset" ]; then
    printf '%s' "$offset"
    return
  fi

  # The file already ends on a line boundary.
  if [ "$(tail -c 1 "$file" | od -An -tu1 | tr -d ' \n')" = "10" ]; then
    printf '%s' "$size"
    return
  fi

  local relative
  relative=$(tail -c +$((offset + 1)) "$file" | LC_ALL=C awk '
    { if (NR > 1) sum += prev + 1; prev = length($0) }
    END { print sum + 0 }')
  printf '%s' $((offset + relative))
}

# Extract final summary from JSON stream output.
# opencode emits complete text parts; the last one is the closing message.
extract_final_summary() {
  local output_file="$1"
  local summary=""

  if [ ! -f "$output_file" ]; then
    echo ""
    return
  fi

  if command -v jq &>/dev/null; then
    summary=$(jq -R 'fromjson? // empty' "$output_file" 2>/dev/null | jq -rs '
      [ .[] | select(.type == "text") | .part.text ] | last // ""' 2>/dev/null)
  fi

  echo "$summary"
}

# Display the final summary with simple separators
display_final_summary() {
  local summary="$1"
  local max_lines="${2:-15}"  # Default to max 15 lines

  if [ -z "$summary" ]; then
    return
  fi

  # Display with simple separators
  echo ""
  echo -e "${C}─────────────────────────────────────────────────────────────────${R}"
  echo -e "${Y}Iteration Summary${R}"
  echo -e "${C}─────────────────────────────────────────────────────────────────${R}"

  # Wrap and display lines (max 70 chars wide, max 15 lines)
  local line_count=0
  local width=70
  while IFS= read -r line || [ -n "$line" ]; do
    while [ ${#line} -gt $width ] && [ $line_count -lt $max_lines ]; do
      # Find last space within width for word wrap
      local cut_at=$width
      local segment="${line:0:$width}"
      local last_space="${segment% *}"
      if [ "$last_space" != "$segment" ] && [ ${#last_space} -gt 20 ]; then
        cut_at=${#last_space}
      fi
      echo "${line:0:$cut_at}"
      line="${line:$cut_at}"
      line="${line# }"  # Remove leading space
      line_count=$((line_count + 1))
    done
    if [ $line_count -lt $max_lines ] && [ -n "$line" ]; then
      echo "$line"
      line_count=$((line_count + 1))
    fi
  done <<< "$summary"

  echo -e "${C}─────────────────────────────────────────────────────────────────${R}"
}
