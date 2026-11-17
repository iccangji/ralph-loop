#!/bin/bash
# Constants module for ralph.sh
# Contains: Colors, paths, version, exit codes, agent minimum versions

# Version
VERSION="2.0.0"

# Minimum agent CLI versions. Agents run on the host, so the installed binary
# decides the version; Ralph refuses anything older than these floors.
MIN_PI_VERSION="1.4.0"
MIN_OPENCODE_VERSION="1.19.0"

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
EXIT_RUNTIME_ERROR=4
EXIT_AUTH_ERROR=5
EXIT_PROVIDER_ERROR=6
