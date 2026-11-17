#!/bin/bash
# Project stack module for ralph.sh
# Optional docker compose helpers
# Dependencies: constants.sh, logging.sh, agents.sh
#
# Docker is optional: a project may run entirely on the host. Every helper
# no-ops when docker, the compose plugin, or a compose file is missing, so a
# project without a stack still completes its tasks.

# Find the project's compose file at the workspace root, if any.
# Usage: find_compose_file
find_compose_file() {
  local candidate
  for candidate in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
    if [ -f "$SCRIPT_DIR/workspace/$candidate" ]; then
      printf "%s" "$SCRIPT_DIR/workspace/$candidate"
      return 0
    fi
  done
  return 1
}

docker_available() {
  command -v docker >/dev/null 2>&1 || return 1
  docker info >/dev/null 2>&1 || return 1
}

# Stable compose project name for this checkout. The agent inherits it through
# COMPOSE_PROJECT_NAME, so the host can tear the stack down afterwards.
compose_project_name() {
  printf "ralph-%s" "$(path_hash "$SCRIPT_DIR")"
}

# Tear down containers the agent started for this project. Best effort: a run
# may have left nothing behind, and a failed teardown must not stop the loop.
down_project_stack() {
  docker_available || return 0

  local project
  local file
  local leftovers
  project=$(compose_project_name)

  leftovers=$(docker ps -aq --filter "label=com.docker.compose.project=$project" 2>/dev/null)
  if [ -z "$leftovers" ]; then
    return 0
  fi

  log_info "Tearing down project containers ($project)..."
  file=$(find_compose_file || true)

  if [ -z "$file" ]; then
    echo "$leftovers" | xargs -r docker rm -f >/dev/null 2>&1 || true
    log_success "Project containers removed"
    return 0
  fi

  if (cd "$SCRIPT_DIR/workspace" &&
    timeout 60 docker compose -p "$project" -f "$file" down -v --remove-orphans >/dev/null 2>&1); then
    log_success "Project containers removed"
  else
    log_warn "Could not tear down project containers ($project); check 'docker ps -a'"
  fi
}
