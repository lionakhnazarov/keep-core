#!/bin/bash
# Check if operators are in sortition pools (RandomBeacon and WalletRegistry)
# Uses cast for fast direct contract calls

set -eou pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

CONFIG_DIR="${CONFIG_DIR:-configs}"
OPERATOR_ADDRESS="${1:-}"  # Optional: specific operator address to check

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get pool addresses
RB_POOL=$(jq -r '.address' solidity/random-beacon/deployments/development/BeaconSortitionPool.json 2>/dev/null || echo "")
WR_POOL=$(jq -r '.address' solidity/ecdsa/deployments/development/EcdsaSortitionPool.json 2>/dev/null || echo "")
RPC="http://localhost:8545"

if [ -z "$RB_POOL" ] || [ "$RB_POOL" = "null" ] || [ -z "$WR_POOL" ] || [ "$WR_POOL" = "null" ]; then
    echo -e "${RED}Error: Could not find pool contract addresses${NC}"
    exit 1
fi

echo "=========================================="
echo "Check Operators in Sortition Pools"
echo "=========================================="
echo ""

# If specific operator address provided, check only that one
if [ -n "$OPERATOR_ADDRESS" ]; then
    echo "Checking operator: $OPERATOR_ADDRESS"
    echo ""
    
    RB=$(cast call "$RB_POOL" "isOperatorInPool(address)(bool)" "$OPERATOR_ADDRESS" --rpc-url "$RPC" 2>/dev/null || echo "error")
    WR=$(cast call "$WR_POOL" "isOperatorInPool(address)(bool)" "$OPERATOR_ADDRESS" --rpc-url "$RPC" 2>/dev/null || echo "error")
    
    echo "RandomBeacon Pool:"
    if [ "$RB" = "true" ]; then
        echo -e "  ${GREEN}✓ In pool${NC}"
    elif [ "$RB" = "false" ]; then
        echo -e "  ${RED}✗ Not in pool${NC}"
    else
        echo -e "  ${YELLOW}? Error checking${NC}"
    fi
    
    echo ""
    echo "WalletRegistry Pool:"
    if [ "$WR" = "true" ]; then
        echo -e "  ${GREEN}✓ In pool${NC}"
    elif [ "$WR" = "false" ]; then
        echo -e "  ${RED}✗ Not in pool${NC}"
    else
        echo -e "  ${YELLOW}? Error checking${NC}"
    fi
    
    exit 0
fi

# Check all operators from node configs
echo "Checking all operators from node configs..."
echo ""

# Find all node config files
NODE_CONFIGS=($(find "$CONFIG_DIR" -name "node*.toml" | sort))

if [ ${#NODE_CONFIGS[@]} -eq 0 ]; then
    echo -e "${YELLOW}No node configs found in $CONFIG_DIR${NC}"
    exit 0
fi

echo "Found ${#NODE_CONFIGS[@]} node config(s)"
echo ""

# Table header
printf "%-10s %-45s %-20s %-20s\n" "Node" "Operator Address" "RandomBeacon" "WalletRegistry"
echo "--------------------------------------------------------------------------------------------------------"

IN_POOL_COUNT=0
NOT_IN_POOL_COUNT=0
ERROR_COUNT=0

for config_file in "${NODE_CONFIGS[@]}"; do
    # Extract node number from filename
    NODE_NUM=$(basename "$config_file" | grep -oE '[0-9]+' || echo "?")
    
    # Get operator address from keyfile
    KEYFILE=$(grep -E "^KeyFile\s*=" "$config_file" 2>/dev/null | cut -d'"' -f2 || echo "")
    
    if [ -z "$KEYFILE" ]; then
        printf "%-10s %-45s %-20s %-20s\n" "node$NODE_NUM" "NOT FOUND" "${RED}ERROR${NC}" "${RED}ERROR${NC}"
        ERROR_COUNT=$((ERROR_COUNT + 1))
        continue
    fi
    
    # Resolve relative paths
    if [[ "$KEYFILE" != /* ]]; then
        KEYFILE="$PROJECT_ROOT/$KEYFILE"
    fi
    
    if [ ! -f "$KEYFILE" ]; then
        printf "%-10s %-45s %-20s %-20s\n" "node$NODE_NUM" "KEYFILE NOT FOUND" "${RED}ERROR${NC}" "${RED}ERROR${NC}"
        ERROR_COUNT=$((ERROR_COUNT + 1))
        continue
    fi
    
    # Extract address from keyfile JSON
    OPERATOR=$(cat "$KEYFILE" 2>/dev/null | jq -r '.address' 2>/dev/null || echo "")
    
    if [ -z "$OPERATOR" ] || [ "$OPERATOR" = "null" ]; then
        # Fallback: extract from filename
        OPERATOR=$(basename "$KEYFILE" | grep -oE '[0-9a-f]{40}$' || echo "")
    fi
    
    if [ -z "$OPERATOR" ]; then
        printf "%-10s %-45s %-20s %-20s\n" "node$NODE_NUM" "ADDRESS NOT FOUND" "${RED}ERROR${NC}" "${RED}ERROR${NC}"
        ERROR_COUNT=$((ERROR_COUNT + 1))
        continue
    fi
    
    # Ensure 0x prefix
    if [[ ! "$OPERATOR" =~ ^0x ]]; then
        OPERATOR="0x$OPERATOR"
    fi
    
    # Check pools using cast
    RB=$(cast call "$RB_POOL" "isOperatorInPool(address)(bool)" "$OPERATOR" --rpc-url "$RPC" 2>/dev/null || echo "error")
    WR=$(cast call "$WR_POOL" "isOperatorInPool(address)(bool)" "$OPERATOR" --rpc-url "$RPC" 2>/dev/null || echo "error")
    
    # Format results
    RB_SYM="${RED}✗${NC}"
    WR_SYM="${RED}✗${NC}"
    
    if [ "$RB" = "true" ]; then
        RB_SYM="${GREEN}✓${NC}"
    elif [ "$RB" = "error" ]; then
        RB_SYM="${YELLOW}?${NC}"
    fi
    
    if [ "$WR" = "true" ]; then
        WR_SYM="${GREEN}✓${NC}"
    elif [ "$WR" = "error" ]; then
        WR_SYM="${YELLOW}?${NC}"
    fi
    
    # Count status
    if [ "$RB" = "true" ] && [ "$WR" = "true" ]; then
        IN_POOL_COUNT=$((IN_POOL_COUNT + 1))
    elif [ "$RB" != "error" ] && [ "$WR" != "error" ]; then
        NOT_IN_POOL_COUNT=$((NOT_IN_POOL_COUNT + 1))
    else
        ERROR_COUNT=$((ERROR_COUNT + 1))
    fi
    
    # Display result
    printf "%-10s %-45s %-20s %-20s\n" \
        "node$NODE_NUM" \
        "$OPERATOR" \
        "$RB_SYM" \
        "$WR_SYM"
done

echo "--------------------------------------------------------------------------------------------------------"
echo ""
echo "Summary:"
echo "  Operators in both pools: $IN_POOL_COUNT"
echo "  Operators NOT in pools: $NOT_IN_POOL_COUNT"
echo "  Errors: $ERROR_COUNT"
echo ""

if [ $NOT_IN_POOL_COUNT -gt 0 ]; then
    echo "To join operators to pools:"
    echo "  ./scripts/join-all-operators-to-pools.sh"
    echo ""
fi

echo "To check a specific operator:"
echo "  ./scripts/check-operator-in-pool.sh <OPERATOR_ADDRESS>"
echo ""
