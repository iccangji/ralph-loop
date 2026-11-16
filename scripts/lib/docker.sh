#!/bin/bash
# Docker module for ralph.sh
# Plain Docker runtime: image build, provider checks, docker run builder
# Dependencies: constants.sh, logging.sh
#
# Ralph runs every agent invocation in an ephemeral container. Only the
# workspace is writable; specs, skills, pi config, and gitconfig are mounted read-only.

# Fail fast when Docker is missing or its daemon is unreachable.
ensure_docker_available() {
  if ! command -v docker >/dev/null 2>&1; then
    log_error "docker is required but was not found on PATH"
    exit $EXIT_DOCKER_ERROR
  fi

  if ! docker info >/dev/null 2>&1; then
    log_error "Docker daemon is not reachable. Start Docker and try again."
    exit $EXIT_DOCKER_ERROR
  fi
}

# Build the pinned pi image once. Later runs reuse the cached image.
ensure_pi_image() {
  if docker image inspect "$PI_IMAGE" >/dev/null 2>&1; then
    return 0
  fi

  log_info "Building $PI_IMAGE (first run only)..."
  if ! docker build \
    --build-arg "PI_VERSION=$PI_VERSION" \
    -t "$PI_IMAGE" \
    -f "$SCRIPT_DIR/Dockerfile.pi" \
    "$SCRIPT_DIR"; then
    log_error "Failed to build $PI_IMAGE"
    exit $EXIT_DOCKER_ERROR
  fi
  log_success "Built $PI_IMAGE"
}

# Verify a loopback provider is reachable from inside the container.
# Skipped entirely when the project models config has no loopback provider.
check_pi_provider_reachable() {
  local models_file="$SCRIPT_DIR/.pi/models.json"
  if [ ! -f "$models_file" ]; then
    return 0
  fi

  local endpoint
  endpoint=$(grep -oE 'host\.docker\.internal:[0-9]+' "$models_file" | head -1)
  if [ -z "$endpoint" ]; then
    return 0
  fi

  log_info "Checking provider reachability from the container ($endpoint)..."
  if docker run --rm \
    --add-host host.docker.internal:host-gateway \
    --entrypoint bash \
    "$PI_IMAGE" -c "curl -s -o /dev/null --max-time 5 http://$endpoint/v1/models" >/dev/null 2>&1; then
    return 0
  fi

  log_error "Cannot reach http://$endpoint from inside the container."
  log_error "The provider in $models_file must be reachable from Docker."
  exit $EXIT_PROVIDER_ERROR
}

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

# GID that owns the Docker socket. The agent runs as the host UID/GID, so it
# needs this supplementary group to reach the daemon.
docker_socket_gid() {
  stat -c %g /var/run/docker.sock 2>/dev/null || true
}

# Stable compose project name for this checkout. The agent inherits it through
# COMPOSE_PROJECT_NAME, so the host can tear the stack down afterwards.
compose_project_name() {
  printf "ralph-%s" "$(path_hash "$SCRIPT_DIR")"
}

# Tear down containers the agent started for this project. Best effort: a run
# may have left nothing behind, and a failed teardown must not stop the loop.
down_project_stack() {
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

  if ( cd "$SCRIPT_DIR/workspace" \
    && timeout 60 docker compose -p "$project" -f "$file" down -v --remove-orphans >/dev/null 2>&1 ); then
    log_success "Project containers removed"
  else
    log_warn "Could not tear down project containers ($project); check 'docker ps -a'"
  fi
}

# Build the shell-quoted `docker run` command for one agent invocation.
# Usage: build_docker_run_command <container-name>
build_docker_run_command() {
  local container_name="$1"
  local workspace="$SCRIPT_DIR/workspace"
  local socket_gid
  socket_gid=$(docker_socket_gid)

  local -a args=(
    docker run --rm
    --name "$container_name"
    --add-host host.docker.internal:host-gateway
    --user "$(id -u):$(id -g)"
    -e HOME=/home/pi
    -e "PROJECT_ROOT=$workspace"
    -e "AGENT_DIR=$SCRIPT_DIR/.agent"
    -e "COMPOSE_PROJECT_NAME=$(compose_project_name)"
    -w "$workspace"
    -v "$workspace:$workspace"
    -v "$SCRIPT_DIR/.agent:$SCRIPT_DIR/.agent:ro"
    # Global skill location: pi discovers ~/.agents/skills regardless of cwd.
    # Project .agents/skills is not reachable, because cwd is the workspace repo.
    -v "$SCRIPT_DIR/.agents:/home/pi/.agents:ro"
    -v /var/run/docker.sock:/var/run/docker.sock
  )

  # The socket is root:docker. Without this group the agent gets EACCES.
  if [ -n "$socket_gid" ]; then
    args+=(--group-add "$socket_gid")
  fi

  if [ -d "$SCRIPT_DIR/.pi" ]; then
    args+=(-v "$SCRIPT_DIR/.pi:/pi-config:ro")
  fi

  if [ -f "$HOME/.gitconfig" ]; then
    args+=(-v "$HOME/.gitconfig:/home/pi/.gitconfig:ro")
  fi

  args+=("$PI_IMAGE")

  printf '%q ' "${args[@]}"
}