#!/bin/bash
# Docker module for ralph.sh
# Plain Docker runtime: image build, config preparation, provider checks
# Dependencies: constants.sh, logging.sh
#
# Ralph runs every agent invocation in an ephemeral container that mounts the
# project at the same absolute path as the host. Only the pi models and settings
# files, the project skills, and the host gitconfig are exposed to the container.

PI_MODELS_SOURCE="$HOME/.pi/agent/models.json"
PI_SETTINGS_SOURCE="$HOME/.pi/agent/settings.json"
PI_MODELS_FILE="$SCRIPT_DIR/.agent/pi/models.json"
GITCONFIG_FILE="$HOME/.gitconfig"

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

# Copy the host pi models config into the project and rewrite loopback provider
# URLs so they resolve to the host from inside the container.
# The host file is never modified.
prepare_pi_models_file() {
  mkdir -p "$(dirname "$PI_MODELS_FILE")"

  if [ ! -f "$PI_MODELS_SOURCE" ]; then
    log_warn "No pi models config at $PI_MODELS_SOURCE; relying on provider env vars"
    rm -f "$PI_MODELS_FILE"
    return 0
  fi

  sed \
    -e 's|http://localhost:|http://host.docker.internal:|g' \
    -e 's|http://127\.0\.0\.1:|http://host.docker.internal:|g' \
    "$PI_MODELS_SOURCE" > "$PI_MODELS_FILE"
}

# Verify the skills directory exists. The canonical source is `.agents/skills`.
# `.agent/skills` and `.claude/skills` symlink to it.
prepare_skill_mount_point() {
  if [ ! -d "$SCRIPT_DIR/.agents/skills" ]; then
    mkdir -p "$SCRIPT_DIR/.agents/skills"
  fi
}

# Verify a loopback provider is reachable from inside the container.
# Skipped entirely when the models config has no loopback provider.
check_pi_provider_reachable() {
  if [ ! -f "$PI_MODELS_FILE" ]; then
    return 0
  fi

  local endpoint
  endpoint=$(grep -oE 'host\.docker\.internal:[0-9]+' "$PI_MODELS_FILE" | head -1)
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
  log_error "The provider in $PI_MODELS_SOURCE is only reachable on the host loopback."
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
    -e PI_CODING_AGENT_DIR=/pi-agent
    -w "$SCRIPT_DIR"
    -v "$SCRIPT_DIR:$SCRIPT_DIR"
  )

  if [ -f "$PI_MODELS_FILE" ]; then
    args+=(-v "$PI_MODELS_FILE:/pi-agent/models.json:ro")
  fi

  if [ -f "$PI_SETTINGS_SOURCE" ]; then
    args+=(-v "$PI_SETTINGS_SOURCE:/pi-agent/settings.json:ro")
  fi

  if [ -f "$GITCONFIG_FILE" ]; then
    args+=(-v "$GITCONFIG_FILE:/home/pi/.gitconfig:ro")
  fi

  args+=("$PI_IMAGE")

  printf '%q ' "${args[@]}"
}
