#!/bin/bash
set -eou pipefail

# Script to start Geth with fast block times (1 second blocks using Clique PoA)
#
# Usage:
#   ./scripts/start-geth-fast.sh [GETH_DATA_DIR] [BLOCK_PERIOD_SECONDS]
#
# Environment variables:
#   GETH_DATA_DIR - Geth data directory (default: ~/ethereum/data)
#   BLOCK_PERIOD - Block period in seconds (default: 1)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
GETH_DATA_DIR="${GETH_DATA_DIR:-$HOME/ethereum/data}"
GETH_DATA_DIR="${1:-$GETH_DATA_DIR}"
BLOCK_PERIOD="${BLOCK_PERIOD:-${2:-1}}"

# Expand ~ in path
EXPANDED_GETH_DATA_DIR=$(eval echo "$GETH_DATA_DIR")

echo "=========================================="
echo "Starting Geth with Fast Block Times"
echo "=========================================="
echo ""
echo "GETH_DATA_DIR: $EXPANDED_GETH_DATA_DIR"
echo "BLOCK_PERIOD: ${BLOCK_PERIOD} seconds"
echo ""
echo "⚠️  NOTE: This uses Clique PoA consensus."
echo "   You need to initialize the chain with Clique-enabled genesis.json"
echo ""

# Check if Geth is already running
if pgrep -f "geth.*--datadir.*$EXPANDED_GETH_DATA_DIR" > /dev/null; then
    echo "⚠️  Geth is already running!"
    echo ""
    echo "To stop it:"
    echo "  pkill -f 'geth.*--datadir.*$EXPANDED_GETH_DATA_DIR'"
    exit 1
fi

# Get signer account (for Clique PoA)
export GETH_ETHEREUM_ACCOUNT="${GETH_ETHEREUM_ACCOUNT:-$(geth account list --keystore "$EXPANDED_GETH_DATA_DIR/keystore" 2>/dev/null | head -1 | grep -o '{[^}]*}' | sed 's/{//;s/}//' | sed 's/^/0x/' || echo "")}"

if [ -z "$GETH_ETHEREUM_ACCOUNT" ]; then
    echo "⚠️  Could not determine signer account"
    echo "   Please set GETH_ETHEREUM_ACCOUNT or create accounts first"
    exit 1
fi

# Copy operator keyfiles to Geth keystore if they don't exist
echo "Copying operator keyfiles to Geth keystore..."
GETH_KEYSTORE="$EXPANDED_GETH_DATA_DIR/keystore"
mkdir -p "$GETH_KEYSTORE"

CONFIG_DIR="$PROJECT_ROOT/configs"
KEYFILES_COPIED=0
for i in {1..10}; do
    CONFIG_FILE="$CONFIG_DIR/node${i}.toml"
    if [ -f "$CONFIG_FILE" ]; then
        KEYFILE=$(grep "^KeyFile" "$CONFIG_FILE" | head -1 | cut -d'"' -f2)
        # Resolve relative path
        if [[ "$KEYFILE" != /* ]]; then
            KEYFILE="$PROJECT_ROOT/$KEYFILE"
        fi
        if [ -n "$KEYFILE" ] && [ -f "$KEYFILE" ]; then
            KEYFILE_NAME=$(basename "$KEYFILE")
            if [ ! -f "$GETH_KEYSTORE/$KEYFILE_NAME" ]; then
                cp "$KEYFILE" "$GETH_KEYSTORE/$KEYFILE_NAME"
                KEYFILES_COPIED=$((KEYFILES_COPIED + 1))
            fi
        fi
    fi
done

if [ $KEYFILES_COPIED -gt 0 ]; then
    echo "  Copied $KEYFILES_COPIED keyfile(s) to Geth keystore"
else
    echo "  All keyfiles already in Geth keystore"
fi

# Extract all operator addresses from node configs
echo "Extracting operator accounts from node configs..."
OPERATOR_ACCOUNTS=()
for i in {1..10}; do
    CONFIG_FILE="$CONFIG_DIR/node${i}.toml"
    if [ -f "$CONFIG_FILE" ]; then
        KEYFILE=$(grep "^KeyFile" "$CONFIG_FILE" | head -1 | cut -d'"' -f2)
        # Resolve relative path
        if [[ "$KEYFILE" != /* ]]; then
            KEYFILE="$PROJECT_ROOT/$KEYFILE"
        fi
        if [ -n "$KEYFILE" ] && [ -f "$KEYFILE" ]; then
            ADDR=$(cat "$KEYFILE" | jq -r .address 2>/dev/null | tr -d '\n')
            if [ -n "$ADDR" ] && [ "$ADDR" != "null" ]; then
                OPERATOR_ACCOUNTS+=("0x$ADDR")
            fi
        fi
    fi
done

# Remove duplicates and sort
UNIQUE_OPERATORS=($(printf '%s\n' "${OPERATOR_ACCOUNTS[@]}" | sort -u))

echo "Signer account: $GETH_ETHEREUM_ACCOUNT"
echo "Operator accounts to unlock: ${#UNIQUE_OPERATORS[@]}"
if [ ${#UNIQUE_OPERATORS[@]} -gt 0 ]; then
    echo "  ${UNIQUE_OPERATORS[@]}"
fi
echo ""
echo "Starting Geth with Clique PoA..."
echo "  Block period: ${BLOCK_PERIOD} seconds"
echo "  RPC: http://localhost:8545"
echo "  WS:  ws://localhost:8546"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Get deployer account (Hardhat uses account index 1 as deployer)
# List accounts and get the second one (index 1)
GETH_ACCOUNTS=$(geth account list --keystore "$EXPANDED_GETH_DATA_DIR/keystore" 2>/dev/null | grep -o '{[^}]*}' | sed 's/{//;s/}//' | sed 's/^/0x/')
DEPLOYER_ACCOUNT=$(echo "$GETH_ACCOUNTS" | sed -n '2p') # Second account (index 1)

# Build unlock flags array
UNLOCK_ARGS=()
UNLOCK_ARGS+=(--unlock "$GETH_ETHEREUM_ACCOUNT")
if [ -n "$DEPLOYER_ACCOUNT" ]; then
    UNLOCK_ARGS+=(--unlock "$DEPLOYER_ACCOUNT")
    echo "Deployer account (for Hardhat): $DEPLOYER_ACCOUNT"
fi
for addr in "${UNIQUE_OPERATORS[@]}"; do
    UNLOCK_ARGS+=(--unlock "$addr")
done

# Check if genesis.json exists and has Clique config
GENESIS_FILE="$EXPANDED_GETH_DATA_DIR/genesis.json"
NEEDS_INIT=false

if [ ! -f "$GENESIS_FILE" ]; then
    echo "Creating genesis.json with Clique PoA (period: ${BLOCK_PERIOD}s)..."
    NEEDS_INIT=true
    
    # Create genesis.json with Clique PoA configuration
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
  "extraData": "0x0000000000000000000000000000000000000000000000000000000000000000${GETH_ETHEREUM_ACCOUNT#0x}0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
  "alloc": {}
}
EOF
    echo "✓ Created genesis.json with Clique PoA (period: ${BLOCK_PERIOD}s)"
elif ! grep -q '"clique"' "$GENESIS_FILE" 2>/dev/null; then
    echo "⚠️  Existing genesis.json doesn't have Clique config"
    echo "   You may need to reset the chain:"
    echo "   rm -rf $EXPANDED_GETH_DATA_DIR/geth"
    echo "   Then run this script again"
fi

# Initialize chain if needed
if [ "$NEEDS_INIT" = true ] || [ ! -d "$EXPANDED_GETH_DATA_DIR/geth/chaindata" ]; then
    if [ "$NEEDS_INIT" = false ]; then
        echo "Chaindata not found, initializing with existing genesis.json..."
    fi
    geth --datadir="$EXPANDED_GETH_DATA_DIR" init "$GENESIS_FILE"
    echo "✓ Chain initialized"
fi

echo ""
echo "Starting Geth with Clique PoA..."
echo "  Block period: ${BLOCK_PERIOD} seconds"
echo "  Signer: $GETH_ETHEREUM_ACCOUNT"
echo "  RPC: http://localhost:8545"
echo "  WS:  ws://localhost:8546"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Start Geth with Clique PoA
geth \
    --port 3000 \
    --networkid 1101 \
    --identity 'local-dev-fast' \
    --ws --ws.addr '127.0.0.1' --ws.port '8546' --ws.origins '*' \
    --ws.api 'admin,debug,web3,eth,txpool,personal,clique,net' \
    --http --http.port '8545' --http.addr '127.0.0.1' --http.corsdomain '' \
    --http.api 'admin,debug,web3,eth,txpool,personal,clique,net' \
    --datadir="$EXPANDED_GETH_DATA_DIR" \
    --allow-insecure-unlock \
    "${UNLOCK_ARGS[@]}" \
    --password <(echo "password") \
    --mine \
    --miner.etherbase="$GETH_ETHEREUM_ACCOUNT" \
    --miner.threads=1
