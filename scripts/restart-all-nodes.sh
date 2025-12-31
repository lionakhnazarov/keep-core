#!/bin/bash
# Script to restart all keep-core nodes

set -eou pipefail

KEEP_CORE_PATH=${KEEP_CORE_PATH:-$PWD}
CONFIG_DIR=${CONFIG_DIR:-"$KEEP_CORE_PATH/configs"}
LOG_DIR=${LOG_DIR:-"$KEEP_CORE_PATH/logs"}
KEEP_ETHEREUM_PASSWORD=${KEEP_ETHEREUM_PASSWORD:-"password"}
LOG_LEVEL=${LOG_LEVEL:-"info"}

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

# Step 1: Stop all running nodes
log_info "Stopping all keep-core nodes..."
pkill -f "keep-client.*start" || {
    log_warning "No keep-client processes found running"
}
sleep 2

# Verify they're stopped
if pgrep -f "keep-client.*start" > /dev/null; then
    log_warning "Some keep-client processes are still running, force killing..."
    pkill -9 -f "keep-client.*start" || true
    sleep 1
fi

log_success "All nodes stopped"

# Step 2: Find all node config files
log_info "Finding node configuration files..."
cd "$KEEP_CORE_PATH"

# Find all node*.toml files
NODE_CONFIGS=()
if [ -d "$CONFIG_DIR" ]; then
    for config in "$CONFIG_DIR"/node*.toml; do
        if [ -f "$config" ]; then
            NODE_CONFIGS+=("$config")
        fi
    done
else
    log_error "Config directory not found: $CONFIG_DIR"
    exit 1
fi

if [ ${#NODE_CONFIGS[@]} -eq 0 ]; then
    log_error "No node*.toml config files found in $CONFIG_DIR"
    exit 1
fi

log_info "Found ${#NODE_CONFIGS[@]} node config file(s)"

# Step 3: Start all nodes
log_info "Starting all nodes..."
mkdir -p "$LOG_DIR"

for config_file in "${NODE_CONFIGS[@]}"; do
    # Extract node number from filename (e.g., node1.toml -> 1)
    node_num=$(basename "$config_file" | sed 's/node\([0-9]*\)\.toml/\1/')
    
    if [ -z "$node_num" ]; then
        log_warning "Could not extract node number from $config_file, skipping..."
        continue
    fi
    
    log_file="$LOG_DIR/node${node_num}.log"
    
    log_info "Starting node $node_num (config: $(basename "$config_file"), log: $log_file)..."
    
    # Start node in background
    cd "$KEEP_CORE_PATH"
    KEEP_ETHEREUM_PASSWORD=$KEEP_ETHEREUM_PASSWORD \
        LOG_LEVEL=$LOG_LEVEL \
        ./keep-client --config "$config_file" start --developer > "$log_file" 2>&1 &
    
    NODE_PID=$!
    echo $NODE_PID > "$LOG_DIR/node${node_num}.pid"
    
    log_success "Node $node_num started (PID: $NODE_PID)"
    
    # Small delay between starts
    sleep 1
done

echo ""
log_success "All nodes restarted!"
echo ""
log_info "Node processes:"
pgrep -af "keep-client.*start" | while read line; do
    echo "  $line"
done
echo ""
log_info "To view logs:"
for config_file in "${NODE_CONFIGS[@]}"; do
    node_num=$(basename "$config_file" | sed 's/node\([0-9]*\)\.toml/\1/')
    if [ -n "$node_num" ]; then
        echo "  Node $node_num: tail -f $LOG_DIR/node${node_num}.log"
    fi
done
echo ""
