#!/bin/bash
set -eou pipefail

# Script to join all operators to sortition pools (RandomBeacon and WalletRegistry)
# Operators must be registered and authorized before joining

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

CONFIG_DIR="${CONFIG_DIR:-./configs}"
PASSWORD="${KEEP_ETHEREUM_PASSWORD:-password}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "=========================================="
echo "Joining Operators to Sortition Pools"
echo "=========================================="
echo ""

# Find all node config files
declare -a CONFIG_FILES
for config_file in "$CONFIG_DIR"/node*.toml; do
    if [ -f "$config_file" ]; then
        CONFIG_FILES+=("$config_file")
    fi
done

if [ ${#CONFIG_FILES[@]} -eq 0 ]; then
    echo "⚠️  No node config files found in $CONFIG_DIR"
    exit 1
fi

echo "Found ${#CONFIG_FILES[@]} node config(s)"
echo ""

# Extract operator addresses from configs
declare -a OPERATORS
declare -a NODE_NUMS

for config_file in "${CONFIG_FILES[@]}"; do
    # Extract node number from filename
    NODE_NUM=$(basename "$config_file" | sed -n 's/node\([0-9]*\)\.toml/\1/p')
    
    if [ -z "$NODE_NUM" ]; then
        continue
    fi
    
    # Get keyfile path
    KEYFILE=$(grep "^KeyFile" "$config_file" | head -1 | cut -d'"' -f2)
    if [ -z "$KEYFILE" ]; then
        continue
    fi
    
    # Resolve relative path
    if [[ "$KEYFILE" != /* ]]; then
        KEYFILE="${KEYFILE#./}"
        KEYFILE="$PROJECT_ROOT/$KEYFILE"
    fi
    
    if [ ! -f "$KEYFILE" ]; then
        continue
    fi
    
    # Extract operator address
    OPERATOR=$(cat "$KEYFILE" | jq -r .address 2>/dev/null | tr -d '\n')
    if [ -z "$OPERATOR" ] || [ "$OPERATOR" = "null" ]; then
        continue
    fi
    
    # Ensure 0x prefix
    if [[ "$OPERATOR" != 0x* ]]; then
        OPERATOR="0x$OPERATOR"
    fi
    
    OPERATORS+=("$OPERATOR")
    NODE_NUMS+=("$NODE_NUM")
    
    echo "Node $NODE_NUM: $OPERATOR"
done

if [ ${#OPERATORS[@]} -eq 0 ]; then
    echo "⚠️  No valid operators found"
    exit 1
fi

echo ""
echo "=========================================="
echo "Joining Sortition Pools"
echo "=========================================="
echo ""

# Join each operator to both RandomBeacon and WalletRegistry sortition pools
SUCCESS_COUNT=0
FAIL_COUNT=0

for i in "${!OPERATORS[@]}"; do
    OPERATOR="${OPERATORS[$i]}"
    NODE_NUM="${NODE_NUMS[$i]}"
    CONFIG_FILE="$CONFIG_DIR/node${NODE_NUM}.toml"
    
    echo "--- Joining Node $NODE_NUM ($OPERATOR) ---"
    
    # Join RandomBeacon sortition pool
    echo "  Joining RandomBeacon sortition pool..."
    if KEEP_ETHEREUM_PASSWORD="$PASSWORD" ./keep-client ethereum beacon random-beacon join-sortition-pool \
        --submit \
        --config "$CONFIG_FILE" \
        --developer 2>&1 | grep -vE "(You are using a version|Please, make sure|To learn more|Error encountered|No need to generate|Contract Name|Size \(KB\)|^ ·|^ \||^---|INFO|using)" | grep -E "(Transaction|hash|SUCCESS|Error|already|joined)" | head -3; then
        echo "    ✓ RandomBeacon pool join submitted"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "    ⚠ RandomBeacon pool join may have failed or already joined"
    fi
    
    sleep 2
    
    # Join WalletRegistry sortition pool
    echo "  Joining WalletRegistry sortition pool..."
    if KEEP_ETHEREUM_PASSWORD="$PASSWORD" ./keep-client ethereum ecdsa wallet-registry join-sortition-pool \
        --submit \
        --config "$CONFIG_FILE" \
        --developer 2>&1 | grep -vE "(You are using a version|Please, make sure|To learn more|Error encountered|No need to generate|Contract Name|Size \(KB\)|^ ·|^ \||^---|INFO|using)" | grep -E "(Transaction|hash|SUCCESS|Error|already|joined)" | head -3; then
        echo "    ✓ WalletRegistry pool join submitted"
    else
        echo "    ⚠ WalletRegistry pool join may have failed or already joined"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    
    sleep 2
    echo ""
done

echo "=========================================="
echo "Join Summary"
echo "=========================================="
echo ""
echo "Successfully joined: $SUCCESS_COUNT"
echo "Failed: $FAIL_COUNT"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo "✅ All operators joined sortition pools successfully!"
    echo ""
    echo "You can now restart nodes:"
    echo "  ./scripts/restart-all-nodes.sh"
else
    echo "⚠️  Some operators failed to join pools"
    echo ""
    echo "You can try joining manually:"
    echo "  KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum beacon random-beacon join-sortition-pool --submit --config configs/node<N>.toml --developer"
    echo "  KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry join-sortition-pool --submit --config configs/node<N>.toml --developer"
fi

echo ""
