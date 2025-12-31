#!/bin/bash
set -eou pipefail

# Script to initialize all operators for multi-node setup
# This runs the initialize Hardhat task for each operator

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

CONFIG_DIR="${CONFIG_DIR:-./configs}"
NETWORK="${NETWORK:-development}"
STAKE_AMOUNT="${STAKE_AMOUNT:-1000000}"  # Default: 1M T tokens
AUTHORIZATION_AMOUNT="${AUTHORIZATION_AMOUNT:-}"  # Default: minimum authorization

KEEP_BEACON_SOL_PATH="$PROJECT_ROOT/solidity/random-beacon"
KEEP_ECDSA_SOL_PATH="$PROJECT_ROOT/solidity/ecdsa"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "=========================================="
echo "Initializing All Operators"
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
echo "Initializing Operators"
echo "=========================================="
echo ""
echo "Network: $NETWORK"
echo "Stake amount: $STAKE_AMOUNT T tokens"
if [ -n "$AUTHORIZATION_AMOUNT" ]; then
    echo "Authorization amount: $AUTHORIZATION_AMOUNT T tokens"
else
    echo "Authorization amount: minimum authorization"
fi
echo ""

# Initialize each operator
SUCCESS_COUNT=0
FAIL_COUNT=0

for i in "${!OPERATORS[@]}"; do
    OPERATOR="${OPERATORS[$i]}"
    NODE_NUM="${NODE_NUMS[$i]}"
    
    echo "--- Initializing Node $NODE_NUM ($OPERATOR) ---"
    
    # Build initialize command
    INIT_CMD="npx hardhat initialize --network $NETWORK --owner $OPERATOR --provider $OPERATOR --operator $OPERATOR --beneficiary $OPERATOR --authorizer $OPERATOR --amount $STAKE_AMOUNT"
    
    if [ -n "$AUTHORIZATION_AMOUNT" ]; then
        INIT_CMD="$INIT_CMD --authorization $AUTHORIZATION_AMOUNT"
    fi
    
    # Initialize RandomBeacon
    echo "  Initializing RandomBeacon..."
    cd "$KEEP_BEACON_SOL_PATH"
    if eval "$INIT_CMD" 2>&1 | grep -vE "(You are using a version|Please, make sure|To learn more|Error encountered|No need to generate|Contract Name|Size \(KB\)|^ ·|^ \||^---)" | grep -E "(✓|SUCCESS|Error|Transaction|hash|already)" | head -5; then
        echo "    ✓ RandomBeacon initialized"
    else
        echo "    ⚠ RandomBeacon initialization may have failed or already initialized"
    fi
    
    sleep 1
    
    # Initialize WalletRegistry
    echo "  Initializing WalletRegistry..."
    cd "$KEEP_ECDSA_SOL_PATH"
    if eval "$INIT_CMD" 2>&1 | grep -vE "(You are using a version|Please, make sure|To learn more|Error encountered|No need to generate|Contract Name|Size \(KB\)|^ ·|^ \||^---)" | grep -E "(✓|SUCCESS|Error|Transaction|hash|already)" | head -5; then
        echo "    ✓ WalletRegistry initialized"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "    ⚠ WalletRegistry initialization may have failed or already initialized"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    
    cd "$PROJECT_ROOT"
    sleep 2
    echo ""
done

echo "=========================================="
echo "Initialization Summary"
echo "=========================================="
echo ""
echo "Successfully initialized: $SUCCESS_COUNT"
echo "Failed: $FAIL_COUNT"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo "✅ All operators initialized successfully!"
    echo ""
    echo "Next steps:"
    echo "  1. Join sortition pools: ./scripts/join-all-operators-to-pools.sh"
    echo "  2. Restart nodes: ./scripts/restart-all-nodes.sh"
else
    echo "⚠️  Some operators failed to initialize"
    echo ""
    echo "You can try initializing manually:"
    echo "  cd solidity/random-beacon"
    echo "  npx hardhat initialize --network development --owner <OPERATOR> --provider <OPERATOR> --operator <OPERATOR> --beneficiary <OPERATOR> --authorizer <OPERATOR> --amount $STAKE_AMOUNT"
    echo "  cd ../ecdsa"
    echo "  npx hardhat initialize --network development --owner <OPERATOR> --provider <OPERATOR> --operator <OPERATOR> --beneficiary <OPERATOR> --authorizer <OPERATOR> --amount $STAKE_AMOUNT"
fi

echo ""
