#!/bin/bash
# Agent module for ralph.sh
# Supported agent CLI and command construction

SUPPORTED_AGENTS="pi"

supported_agents_list() {
  echo "$SUPPORTED_AGENTS"
}

normalize_agent_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

is_supported_agent() {
  case "$1" in
    pi)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

agent_display_name() {
  case "$1" in
    pi) echo "Pi" ;;
    *) echo "$1" ;;
  esac
}

agent_login_command() {
  echo "pi"
}

sanitize_name_segment() {
  local value="${1:-project}"
  value=$(printf "%s" "$value" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')
  if [ -z "$value" ]; then
    value="project"
  fi
  printf "%s" "$value"
}

path_hash() {
  local project_path="$1"
  if command -v shasum >/dev/null 2>&1; then
    printf "%s" "$project_path" | shasum -a 256 | awk '{print substr($1, 1, 8)}'
  elif command -v sha256sum >/dev/null 2>&1; then
    printf "%s" "$project_path" | sha256sum | awk '{print substr($1, 1, 8)}'
  else
    printf "%s" "$project_path" | cksum | awk '{printf "%08x", $1}'
  fi
}

build_container_name() {
  local agent="${1:-pi}"
  local project_path="${2:-$PWD}"
  local safe_agent
  local safe_project
  local hash
  safe_agent=$(sanitize_name_segment "$agent")
  safe_project=$(sanitize_name_segment "$(basename "$project_path")")
  hash=$(path_hash "$project_path")
  printf "ralph-%s-%s-%s" "$safe_agent" "$safe_project" "$hash"
}

format_agent_extra_args() {
  local output=""
  local arg
  local quoted
  for arg in "${AGENT_EXTRA_ARGS[@]}"; do
    printf -v quoted "%q" "$arg"
    output="$output $quoted"
  done
  printf "%s" "$output"
}

build_agent_command() {
  local container_name="${1:-}"
  local extra_args
  local docker_run
  extra_args=$(format_agent_extra_args)
  docker_run=$(build_docker_run_command "$container_name")

  if [ -n "$extra_args" ]; then
    printf '%s --mode json --approve --no-session %s "$PROMPT_CONTENT"' "$docker_run" "$extra_args"
  else
    printf '%s --mode json --approve --no-session "$PROMPT_CONTENT"' "$docker_run"
  fi
}