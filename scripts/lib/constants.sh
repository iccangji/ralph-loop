#!/bin/bash
# Constants module for ralph.sh
# Contains: Colors, paths, version, exit codes

# Version
VERSION="1.0.0"

# Pinned pi coding agent version and the Docker image Ralph builds from it
PI_VERSION="1.5.2"
PI_IMAGE="ralph-pi:$PI_VERSION"

# Colors (short syntax)
Y='\033[33m'        # Yellow
B='\033[94m'        # Light blue
G='\033[1;90m'      # Grey bold
C='\033[36m'        # Cyan
M='\033[35m'        # Magenta
GR='\033[32m'       # Green
RD='\033[31m'       # Red
D='\033[2m'         # Dim
R='\033[0m'         # Reset

# Exit codes
EXIT_COMPLETE=0
EXIT_MAX_ITERATIONS=1
EXIT_BLOCKED=2
EXIT_DECIDE=3
EXIT_DOCKER_ERROR=4
EXIT_AUTH_ERROR=5
EXIT_PROVIDER_ERROR=6
