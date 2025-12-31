#!/bin/bash
# Fix "operator not registered for the staking provider" error
# This script registers operators that are not registered

set -eou pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

CONFIG_DIR="${CONFIG_DIR:-configs}"
NODE_NUM="${1:-}"  # Optional: specific node number to fix

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "Fix Operator Not Registered Error"
echo "=========================================="
echo ""

# Function to get operator address from config
get_operator_from_config() {
    local config_file="$1"
    local keyfile=$(grep -E "^KeyFile\s*=" "$config_file" 2>/dev/null | cut -d'"' -f2 || echo "")
    
    if [ -z "$keyfile" ]; then
        echo ""
        return
    fi
    
    if [[ "$keyfile" != /* ]]; then
        keyfile="$PROJECT_ROOT/$keyfile"
    fi
    
    if [ ! -f "$keyfile" ]; then
        echo ""
        return
    fi
    
    local address=$(cat "$keyfile" 2>/dev/null | jq -r '.address' 2>/dev/null || echo "")
    
    if [ -z "$address" ] || [ "$address" = "null" ]; then
        address=$(basename "$keyfile" | grep -oE '[0-9a-f]{40}$' || echo "")
    fi
    
    if [ -n "$address" ] && [[ ! "$address" =~ ^0x ]]; then
        address="0x$address"
    fi
    
    echo "$address"
}

# Function to check if operator is registered
is_operator_registered() {
    local operator="$1"
    local config_file="$2"
    local pool_type="$3"  # "beacon" or "ecdsa"
    
    local result=""
    if [ "$pool_type" = "beacon" ]; then
        result=$(KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum beacon random-beacon operator-to-staking-provider \
            "$operator" \
            --config "$config_file" \
            --developer 2>&1 | grep -oE "0x[0-9a-f]{40}" | head -1 || echo "")
    else
        result=$(KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry operator-to-staking-provider \
            "$operator" \
            --config "$config_file" \
            --developer 2>&1 | grep -oE "0x[0-9a-f]{40}" | head -1 || echo "")
    fi
    
    if [ "$result" = "0x0000000000000000000000000000000000000000" ] || [ -z "$result" ]; then
        return 1  # Not registered
    else
        return 0  # Registered
    fi
}

# Function to register operator
register_operator() {
    local operator="$1"
    local config_file="$2"
    local pool_type="$3"  # "beacon" or "ecdsa"
    
    echo "  Registering in ${pool_type^}..."
    
    if [ "$pool_type" = "beacon" ]; then
        KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum beacon random-beacon register-operator \
            "$operator" \
            --submit \
            --config "$config_file" \
            --developer >/dev/null 2>&1
    else
        KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry register-operator \
            "$operator" \
            --submit \
            --config "$config_file" \
            --developer >/dev/null 2>&1
    fi
    
    sleep 2
}

# If specific node number provided, fix only that one
if [ -n "$NODE_NUM" ]; then
    CONFIG_FILE="$CONFIG_DIR/node${NODE_NUM}.toml"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}Error: Config file not found: $CONFIG_FILE${NC}"
        exit 1
    fi
    
    OPERATOR=$(get_operator_from_config "$CONFIG_FILE")
    
    if [ -z "$OPERATOR" ]; then
        echo -e "${RED}Error: Could not extract operator address from $CONFIG_FILE${NC}"
        exit 1
    fi
    
    echo "Fixing Node $NODE_NUM (Operator: $OPERATOR)"
    echo ""
    
    RB_REGISTERED=false
    WR_REGISTERED=false
    
    if is_operator_registered "$OPERATOR" "$CONFIG_FILE" "beacon"; then
        echo -e "${GREEN}✓${NC} RandomBeacon: Already registered"
        RB_REGISTERED=true
    else
        echo -e "${YELLOW}✗${NC} RandomBeacon: Not registered"
        register_operator "$OPERATOR" "$CONFIG_FILE" "beacon"
        if is_operator_registered "$OPERATOR" "$CONFIG_FILE" "beacon"; then
            echo -e "${GREEN}✓${NC} RandomBeacon: Registered successfully"
            RB_REGISTERED=true
        else
            echo -e "${RED}✗${NC} RandomBeacon: Registration failed"
        fi
    fi
    
    echo ""
    
    if is_operator_registered "$OPERATOR" "$CONFIG_FILE" "ecdsa"; then
        echo -e "${GREEN}✓${NC} WalletRegistry: Already registered"
        WR_REGISTERED=true
    else
        echo -e "${YELLOW}✗${NC} WalletRegistry: Not registered"
        register_operator "$OPERATOR" "$CONFIG_FILE" "ecdsa"
        if is_operator_registered "$OPERATOR" "$CONFIG_FILE" "ecdsa"; then
            echo -e "${GREEN}✓${NC} WalletRegistry: Registered successfully"
            WR_REGISTERED=true
        else
            echo -e "${RED}✗${NC} WalletRegistry: Registration failed"
        fi
    fi
    
    echo ""
    if [ "$RB_REGISTERED" = "true" ] && [ "$WR_REGISTERED" = "true" ]; then
        echo -e "${GREEN}✓ Operator is now registered in both pools${NC}"
        echo ""
        echo "You can now restart the node:"
        echo "  ./scripts/restart-all-nodes.sh"
    else
        echo -e "${YELLOW}⚠ Some registrations may have failed${NC}"
    fi
    
    exit 0
fi

# Fix all nodes
echo "Checking all operators..."
echo ""

NODE_CONFIGS=($(find "$CONFIG_DIR" -name "node*.toml" | sort))
FIXED_COUNT=0
ALREADY_REGISTERED=0
FAILED_COUNT=0

for config_file in "${NODE_CONFIGS[@]}"; do
    NODE_NUM=$(basename "$config_file" | grep -oE '[0-9]+' || echo "?")
    OPERATOR=$(get_operator_from_config "$config_file")
    
    if [ -z "$OPERATOR" ]; then
        echo -e "${RED}node$NODE_NUM: Could not extract operator address${NC}"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        continue
    fi
    
    RB_NEEDS_FIX=false
    WR_NEEDS_FIX=false
    
    if ! is_operator_registered "$OPERATOR" "$config_file" "beacon"; then
        RB_NEEDS_FIX=true
    fi
    
    if ! is_operator_registered "$OPERATOR" "$config_file" "ecdsa"; then
        WR_NEEDS_FIX=true
    fi
    
    if [ "$RB_NEEDS_FIX" = "false" ] && [ "$WR_NEEDS_FIX" = "false" ]; then
        echo -e "${GREEN}node$NODE_NUM${NC}: Already registered"
        ALREADY_REGISTERED=$((ALREADY_REGISTERED + 1))
        continue
    fi
    
    echo -e "${BLUE}node$NODE_NUM${NC}: Fixing registration..."
    
    if [ "$RB_NEEDS_FIX" = "true" ]; then
        register_operator "$OPERATOR" "$config_file" "beacon"
    fi
    
    if [ "$WR_NEEDS_FIX" = "true" ]; then
        register_operator "$OPERATOR" "$config_file" "ecdsa"
    fi
    
    # Verify
    RB_OK=false
    WR_OK=false
    
    if is_operator_registered "$OPERATOR" "$config_file" "beacon"; then
        RB_OK=true
    fi
    
    if is_operator_registered "$OPERATOR" "$config_file" "ecdsa"; then
        WR_OK=true
    fi
    
    if [ "$RB_OK" = "true" ] && [ "$WR_OK" = "true" ]; then
        echo -e "${GREEN}  ✓ Registered${NC}"
        FIXED_COUNT=$((FIXED_COUNT + 1))
    else
        echo -e "${RED}  ✗ Registration may have failed${NC}"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
    
    echo ""
done

echo "=========================================="
echo "Summary"
echo "=========================================="
echo "  Already registered: $ALREADY_REGISTERED"
echo "  Fixed: $FIXED_COUNT"
echo "  Failed: $FAILED_COUNT"
echo ""

if [ $FIXED_COUNT -gt 0 ]; then
    echo "Restart nodes to apply changes:"
    echo "  ./scripts/restart-all-nodes.sh"
fi
