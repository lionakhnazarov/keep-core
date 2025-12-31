#!/bin/bash
set -eou pipefail

# Script to register all operators for multi-node setup
# This uses keyfiles directly to avoid Hardhat account access issues

NUM_NODES=${1:-10}
CONFIG_DIR=${2:-./configs}
PASSWORD=${KEEP_ETHEREUM_PASSWORD:-password}

echo "=========================================="
echo "Registering All Operators"
echo "=========================================="
echo ""

# Extract keyfile paths from configs
declare -a KEYFILES
for i in $(seq 1 $NUM_NODES); do
    CONFIG_FILE="$CONFIG_DIR/node${i}.toml"
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "⚠ Warning: Config file not found: $CONFIG_FILE"
        continue
    fi
    
    KEYFILE=$(grep "^KeyFile" "$CONFIG_FILE" | head -1 | cut -d'"' -f2)
    if [ -z "$KEYFILE" ]; then
        echo "⚠ Warning: KeyFile not found in $CONFIG_FILE"
        continue
    fi
    
    # Resolve relative path
    # KeyFile paths in configs are relative to project root, not config directory
    if [[ "$KEYFILE" != /* ]]; then
        # Remove leading ./ if present
        KEYFILE="${KEYFILE#./}"
        # If path doesn't start with /, resolve relative to project root
        # Get project root (parent of scripts directory)
        PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
        KEYFILE="$PROJECT_ROOT/$KEYFILE"
    fi
    
    if [ ! -f "$KEYFILE" ]; then
        echo "⚠ Warning: KeyFile not found: $KEYFILE"
        continue
    fi
    
    KEYFILES[$i]="$KEYFILE"
    
    # Extract address for display
    ADDR=$(cat "$KEYFILE" | jq -r .address 2>/dev/null | tr -d '\n')
    if [ -n "$ADDR" ] && [ "$ADDR" != "null" ]; then
        echo "Node $i: 0x$ADDR"
    else
        echo "Node $i: $KEYFILE"
    fi
done

echo ""
echo "=========================================="
echo "Registering Operators"
echo "=========================================="
echo ""

# Register each operator using the keyfile-based script
for i in $(seq 1 $NUM_NODES); do
    # Use default empty value to avoid unbound variable error
    KEYFILE="${KEYFILES[$i]:-}"
    if [ -z "$KEYFILE" ]; then
        echo "⚠ Skipping node $i (no keyfile)"
        continue
    fi
    
    echo "--- Registering Node $i ---"
    echo "Keyfile: $KEYFILE"
    
    cd solidity/ecdsa
    # If KEYFILE is absolute, use it as-is. Otherwise, make it relative to solidity/ecdsa
    if [[ "$KEYFILE" == /* ]]; then
        # Absolute path - use as-is
        KEYFILE_ARG="$KEYFILE"
    else
        # Relative path - make relative to solidity/ecdsa (two levels up)
        KEYFILE_ARG="../../$KEYFILE"
    fi
    
    if KEYFILE="$KEYFILE_ARG" KEEP_ETHEREUM_PASSWORD="$PASSWORD" npx hardhat run scripts/register-operator-from-keyfile.ts --network development 2>&1 | grep -v "You are using a version" | grep -v "Please, make sure" | grep -v "To learn more" | grep -v "Error encountered" | grep -v "No need to generate" | grep -v "Contract Name" | grep -v "Size (KB)" | grep -v "^ ·" | grep -v "^ |" | grep -v "^---" | grep -E "(===|✓|❌|Error|SUCCESS|Operator|Transaction|hash)" | head -30; then
        echo "  ✓ Node $i registered"
    else
        echo "  ⚠ Node $i registration had issues (check output above)"
    fi
    
    cd ../..
    echo ""
done

echo "=========================================="
echo "Registration Complete!"
echo "=========================================="
echo ""
echo "You can now restart nodes:"
echo "  ./configs/start-all-nodes.sh"
