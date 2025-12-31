#!/bin/bash
set -eou pipefail

# Script to copy operator keyfiles to Geth keystore
# This ensures Geth can unlock operator accounts

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default Geth data directory
GETH_DATA_DIR="${GETH_DATA_DIR:-$HOME/ethereum/data}"
GETH_DATA_DIR="${1:-$GETH_DATA_DIR}"

# Expand ~ in path
EXPANDED_GETH_DATA_DIR=$(eval echo "$GETH_DATA_DIR")
GETH_KEYSTORE="$EXPANDED_GETH_DATA_DIR/keystore"

echo "=========================================="
echo "Copying Operator Keyfiles to Geth Keystore"
echo "=========================================="
echo ""
echo "Geth keystore: $GETH_KEYSTORE"
echo ""

# Create keystore directory if it doesn't exist
mkdir -p "$GETH_KEYSTORE"

# Copy operator keyfiles
CONFIG_DIR="$PROJECT_ROOT/configs"
KEYFILES_COPIED=0
KEYFILES_SKIPPED=0

for i in {1..10}; do
    CONFIG_FILE="$CONFIG_DIR/node${i}.toml"
    if [ ! -f "$CONFIG_FILE" ]; then
        continue
    fi
    
    KEYFILE=$(grep "^KeyFile" "$CONFIG_FILE" | head -1 | cut -d'"' -f2)
    if [ -z "$KEYFILE" ]; then
        continue
    fi
    
    # Resolve relative path
    if [[ "$KEYFILE" != /* ]]; then
        KEYFILE="$PROJECT_ROOT/$KEYFILE"
    fi
    
    if [ ! -f "$KEYFILE" ]; then
        echo "⚠️  Warning: Keyfile not found: $KEYFILE"
        continue
    fi
    
    KEYFILE_NAME=$(basename "$KEYFILE")
    DEST="$GETH_KEYSTORE/$KEYFILE_NAME"
    
    if [ -f "$DEST" ]; then
        echo "  ✓ Already exists: $KEYFILE_NAME"
        KEYFILES_SKIPPED=$((KEYFILES_SKIPPED + 1))
    else
        cp "$KEYFILE" "$DEST"
        echo "  ✓ Copied: $KEYFILE_NAME"
        KEYFILES_COPIED=$((KEYFILES_COPIED + 1))
    fi
done

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo "Copied: $KEYFILES_COPIED"
echo "Already existed: $KEYFILES_SKIPPED"
echo ""
echo "Keyfiles are now in: $GETH_KEYSTORE"
echo ""
echo "You can now restart Geth to unlock these accounts:"
echo "  ./scripts/start-geth-fast.sh"
