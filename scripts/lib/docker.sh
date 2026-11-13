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

# Build the shell-quoted `docker run` command for one agent invocation.
# Usage: build_docker_run_command <container-name>
build_docker_run_command() {
  local container_name="$1"
  local -a args=(
    docker run --rm
    --name "$container_name"
    --add-host host.docker.internal:host-gateway
    --user "$(id -u):$(id -g)"
    -e HOME=/home/pi
    -w /workspace
    -v "$SCRIPT_DIR/workspace:/workspace"
    -v "$SCRIPT_DIR/.agent:/workspace/.agent:ro"
    -v "$SCRIPT_DIR/.agents:/workspace/.agents:ro"
  )

  if [ -d "$SCRIPT_DIR/.pi" ]; then
    args+=(-v "$SCRIPT_DIR/.pi:/pi-config:ro")
  fi

  if [ -f "$HOME/.gitconfig" ]; then
    args+=(-v "$HOME/.gitconfig:/home/pi/.gitconfig:ro")
  fi

  args+=("$PI_IMAGE")

  printf '%q ' "${args[@]}"
}