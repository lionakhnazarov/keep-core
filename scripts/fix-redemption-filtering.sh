#!/bin/bash
# Script to fix redemption event filtering by:
# 1. Redeploying Bridge stub with redemptionParameters() function
# 2. Rebuilding Go binary with increased filterStartBlock safety margin
# 3. Restarting all nodes

set -eou pipefail

cd "$(dirname "$0")/.."

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

# Step 1: Compile Bridge stub contract
log_info "Step 1: Compiling Bridge stub contract..."
cd solidity/tbtc-stub
if ! npx hardhat compile > /dev/null 2>&1; then
    log_error "Failed to compile Bridge stub contract"
    exit 1
fi
log_success "Bridge stub contract compiled"
cd ../..

# Step 2: Redeploy Bridge stub
log_info "Step 2: Redeploying Bridge stub with redemptionParameters() function..."
cd solidity/tbtc-stub

# Force delete existing Bridge deployment to ensure fresh deployment
if [ -f "deployments/development/Bridge.json" ]; then
    log_warning "Deleting existing Bridge deployment to force redeployment..."
    rm -f deployments/development/Bridge.json
    rm -f deployments/development/BridgeStub.json
fi

# Deploy Bridge stub
if ! npx hardhat deploy --tags TBTCStubs --network development > /dev/null 2>&1; then
    log_error "Failed to deploy Bridge stub"
    exit 1
fi

# Get new Bridge address
NEW_BRIDGE_ADDRESS=$(jq -r '.address' deployments/development/Bridge.json 2>/dev/null || echo "")
if [ -z "$NEW_BRIDGE_ADDRESS" ] || [ "$NEW_BRIDGE_ADDRESS" = "null" ]; then
    log_error "Failed to get new Bridge address from deployment"
    exit 1
fi

log_success "Bridge stub redeployed at: $NEW_BRIDGE_ADDRESS"

# Verify redemptionParameters function exists
log_info "Verifying redemptionParameters() function..."
RPC_URL="http://localhost:8545"
if cast call "$NEW_BRIDGE_ADDRESS" "redemptionParameters()" --rpc-url "$RPC_URL" > /dev/null 2>&1; then
    log_success "redemptionParameters() function verified"
else
    log_error "redemptionParameters() function not found - deployment may have failed"
    exit 1
fi

cd ../..

# Step 3: Update Bridge address file if it changed
log_info "Step 3: Updating Bridge address file..."
BRIDGE_ADDRESS_FILE="pkg/chain/ethereum/tbtc/gen/_address/Bridge"
CURRENT_ADDRESS=$(cat "$BRIDGE_ADDRESS_FILE" 2>/dev/null || echo "")
if [ "$CURRENT_ADDRESS" != "$NEW_BRIDGE_ADDRESS" ]; then
    log_warning "Bridge address changed from $CURRENT_ADDRESS to $NEW_BRIDGE_ADDRESS"
    echo "$NEW_BRIDGE_ADDRESS" > "$BRIDGE_ADDRESS_FILE"
    log_success "Bridge address file updated"
else
    log_info "Bridge address unchanged: $NEW_BRIDGE_ADDRESS"
fi

# Step 4: Update WalletRegistry walletOwner if needed
log_info "Step 4: Checking WalletRegistry walletOwner..."
cd solidity/ecdsa
WALLET_REGISTRY_ADDRESS=$(jq -r '.address' deployments/development/WalletRegistry.json 2>/dev/null || echo "")
if [ -n "$WALLET_REGISTRY_ADDRESS" ] && [ "$WALLET_REGISTRY_ADDRESS" != "null" ]; then
    CURRENT_OWNER=$(cast call "$WALLET_REGISTRY_ADDRESS" "walletOwner()" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
    if [ "$CURRENT_OWNER" != "$NEW_BRIDGE_ADDRESS" ]; then
        log_warning "WalletRegistry walletOwner ($CURRENT_OWNER) != Bridge address ($NEW_BRIDGE_ADDRESS)"
        log_info "You may need to update walletOwner manually using update-wallet-owner task"
    else
        log_success "WalletRegistry walletOwner is correct"
    fi
fi
cd ../..

# Step 5: Rebuild Go binary
log_info "Step 5: Rebuilding Go binary with new filterStartBlock code..."
if ! make build > /dev/null 2>&1; then
    log_error "Failed to build Go binary"
    exit 1
fi
log_success "Go binary rebuilt successfully"

# Step 6: Stop all nodes
log_info "Step 6: Stopping all nodes..."
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

# Step 7: Restart all nodes
log_info "Step 7: Restarting all nodes..."
CONFIG_DIR=${CONFIG_DIR:-"$PWD/configs"}
LOG_DIR=${LOG_DIR:-"$PWD/logs"}
KEEP_ETHEREUM_PASSWORD=${KEEP_ETHEREUM_PASSWORD:-"password"}
LOG_LEVEL=${LOG_LEVEL:-"info"}

mkdir -p "$LOG_DIR"

# Find all node config files
NODE_CONFIGS=()
if [ -d "$CONFIG_DIR" ]; then
    for config in "$CONFIG_DIR"/node*.toml; do
        if [ -f "$config" ]; then
            NODE_CONFIGS+=("$config")
        fi
    done
fi

if [ ${#NODE_CONFIGS[@]} -eq 0 ]; then
    log_error "No node*.toml config files found in $CONFIG_DIR"
    exit 1
fi

log_info "Found ${#NODE_CONFIGS[@]} node config file(s)"

for config_file in "${NODE_CONFIGS[@]}"; do
    node_num=$(basename "$config_file" | sed 's/node\([0-9]*\)\.toml/\1/')
    
    if [ -z "$node_num" ]; then
        log_warning "Could not extract node number from $config_file, skipping..."
        continue
    fi
    
    log_file="$LOG_DIR/node${node_num}.log"
    
    log_info "Starting node $node_num..."
    
    KEEP_ETHEREUM_PASSWORD=$KEEP_ETHEREUM_PASSWORD \
        LOG_LEVEL=$LOG_LEVEL \
        ./keep-client --config "$config_file" start --developer > "$log_file" 2>&1 &
    
    NODE_PID=$!
    echo $NODE_PID > "$LOG_DIR/node${node_num}.pid"
    
    log_success "Node $node_num started (PID: $NODE_PID)"
    
    sleep 1
done

echo ""
log_success "All steps completed successfully!"
echo ""
log_info "Summary:"
echo "  - Bridge stub redeployed at: $NEW_BRIDGE_ADDRESS"
echo "  - Bridge address file updated"
echo "  - Go binary rebuilt with increased filterStartBlock safety margin (10000 blocks)"
echo "  - All nodes restarted"
echo ""
log_info "Next steps:"
echo "  1. Wait for nodes to sync and reach the next coordination window"
echo "  2. Submit a new redemption request or wait for existing one to be detected"
echo "  3. Monitor logs: tail -f logs/node*.log | grep -i redemption"
echo ""
log_info "To check if redemptionParameters() is working:"
echo "  cast call $NEW_BRIDGE_ADDRESS \"redemptionParameters()\" --rpc-url http://localhost:8545"
echo ""
