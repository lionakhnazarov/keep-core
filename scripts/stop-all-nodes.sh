#!/bin/bash
# Script to stop all keep-core nodes

set -eou pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_info "Stopping all keep-core nodes..."

# Check if any nodes are running
if ! pgrep -f "keep-client.*start" > /dev/null; then
    log_warning "No keep-client processes found running"
    exit 0
fi

# Show running processes
log_info "Found running keep-client processes:"
pgrep -af "keep-client.*start" | while read line; do
    echo "  $line"
done
echo ""

# Stop gracefully first
log_info "Sending SIGTERM to all keep-client processes..."
pkill -f "keep-client.*start" || true
sleep 2

# Check if any are still running
if pgrep -f "keep-client.*start" > /dev/null; then
    log_warning "Some processes didn't stop gracefully, force killing..."
    pkill -9 -f "keep-client.*start" || true
    sleep 1
fi

# Verify they're stopped
if pgrep -f "keep-client.*start" > /dev/null; then
    log_error "Failed to stop some processes"
    exit 1
else
    log_success "All nodes stopped"
fi
