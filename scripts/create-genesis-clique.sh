#!/bin/bash
set -eou pipefail

# Script to create a Clique PoA genesis file for fast block times
#
# Usage:
#   ./scripts/create-genesis-clique.sh [GETH_DATA_DIR] [BLOCK_PERIOD] [SIGNER_ADDRESS]
#
# Environment variables:
#   GETH_DATA_DIR - Geth data directory (default: ~/ethereum/data)
#   BLOCK_PERIOD - Block period in seconds (default: 1)
#   SIGNER_ADDRESS - Address to use as signer (auto-detected if not set)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
GETH_DATA_DIR="${GETH_DATA_DIR:-$HOME/ethereum/data}"
GETH_DATA_DIR="${1:-$GETH_DATA_DIR}"
BLOCK_PERIOD="${BLOCK_PERIOD:-${2:-1}}"
SIGNER_ADDRESS="${SIGNER_ADDRESS:-${3:-}}"

# Expand ~ in path
EXPANDED_GETH_DATA_DIR=$(eval echo "$GETH_DATA_DIR")

echo "=========================================="
echo "Creating Clique PoA Genesis File"
echo "=========================================="
echo ""
echo "GETH_DATA_DIR: $EXPANDED_GETH_DATA_DIR"
echo "BLOCK_PERIOD: ${BLOCK_PERIOD} seconds"
echo ""

# Get signer address
if [ -z "$SIGNER_ADDRESS" ]; then
    if [ -d "$EXPANDED_GETH_DATA_DIR/keystore" ]; then
        SIGNER_ADDRESS=$(geth account list --keystore "$EXPANDED_GETH_DATA_DIR/keystore" 2>/dev/null | head -1 | grep -o '{[^}]*}' | sed 's/{//;s/}//' | sed 's/^/0x/' || echo "")
    fi
fi

if [ -z "$SIGNER_ADDRESS" ]; then
    echo "⚠️  Could not determine signer address"
    echo "   Please create accounts first or set SIGNER_ADDRESS"
    exit 1
fi

echo "Signer address: $SIGNER_ADDRESS"
echo ""

# Get all accounts for genesis allocation
ACCOUNTS=$(geth account list --keystore "$EXPANDED_GETH_DATA_DIR/keystore" 2>/dev/null | grep -o '{[^}]*}' | sed 's/{//;s/}//' | head -15 || echo "")

# Create Clique genesis.json
GENESIS_FILE="$EXPANDED_GETH_DATA_DIR/genesis.json"

cat > "$GENESIS_FILE" <<EOF
{
  "config": {
    "chainId": 1101,
    "homesteadBlock": 0,
    "eip150Block": 0,
    "eip155Block": 0,
    "eip158Block": 0,
    "byzantiumBlock": 0,
    "constantinopleBlock": 0,
    "petersburgBlock": 0,
    "istanbulBlock": 0,
    "clique": {
      "period": ${BLOCK_PERIOD},
      "epoch": 30000
    }
  },
  "difficulty": "0x1",
  "gasLimit": "0x7A1200",
  "extraData": "0x0000000000000000000000000000000000000000000000000000000000000000${SIGNER_ADDRESS#0x}0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
  "alloc": {
EOF

# Add accounts to alloc
FIRST=true
for addr in $ACCOUNTS; do
    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        echo "," >> "$GENESIS_FILE"
    fi
    echo "    \"0x$addr\": { \"balance\": \"1000000000000000000000000000000000000000000000000000000\" }" | tr -d '\n' >> "$GENESIS_FILE"
done

cat >> "$GENESIS_FILE" <<EOF

  }
}
EOF

echo "✓ Created Clique genesis file: $GENESIS_FILE"
echo ""
echo "Block period: ${BLOCK_PERIOD} seconds"
echo "Signer: $SIGNER_ADDRESS"
echo ""
echo "Next steps:"
echo "  1. Initialize chain: geth --datadir=\"$EXPANDED_GETH_DATA_DIR\" init \"$GENESIS_FILE\""
echo "  2. Start Geth: ./scripts/start-geth-fast.sh"
echo ""
