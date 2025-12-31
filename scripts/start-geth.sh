#!/bin/bash
set -eou pipefail

# Script to start Geth for local development
#
# Usage:
#   ./scripts/start-geth.sh [GETH_DATA_DIR]
#
# Environment variables:
#   GETH_DATA_DIR - Geth data directory (default: ~/ethereum/data)
#   GETH_ETHEREUM_ACCOUNT - Mining account (auto-detected if not set)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
GETH_DATA_DIR="${GETH_DATA_DIR:-$HOME/ethereum/data}"
GETH_DATA_DIR="${1:-$GETH_DATA_DIR}"

# Expand ~ in path
EXPANDED_GETH_DATA_DIR=$(eval echo "$GETH_DATA_DIR")

echo "=========================================="
echo "Starting Geth for Local Development"
echo "=========================================="
echo ""
echo "GETH_DATA_DIR: $EXPANDED_GETH_DATA_DIR"
echo ""

# Check if Geth is already running
if pgrep -f "geth.*--datadir.*$EXPANDED_GETH_DATA_DIR" > /dev/null; then
    echo "⚠️  Geth is already running!"
    echo ""
    echo "To stop it:"
    echo "  pkill -f 'geth.*--datadir.*$EXPANDED_GETH_DATA_DIR'"
    echo ""
    echo "Or check if it's responding:"
    echo "  curl -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' http://localhost:8545"
    exit 1
fi

# Check if chain is initialized
if [ ! -d "$EXPANDED_GETH_DATA_DIR/geth" ]; then
    echo "⚠️  Chain not initialized!"
    echo ""
    echo "Please initialize the chain first:"
    echo "  geth --datadir=\"$EXPANDED_GETH_DATA_DIR\" init \"$EXPANDED_GETH_DATA_DIR/genesis.json\""
    echo ""
    echo "Or run the full reset script:"
    echo "  ./scripts/reset-local-setup.sh"
    exit 1
fi

# Get mining account
export GETH_ETHEREUM_ACCOUNT="${GETH_ETHEREUM_ACCOUNT:-$(geth account list --keystore "$EXPANDED_GETH_DATA_DIR/keystore" 2>/dev/null | head -1 | grep -o '{[^}]*}' | sed 's/{//;s/}//' | sed 's/^/0x/' || echo "")}"

if [ -z "$GETH_ETHEREUM_ACCOUNT" ]; then
    echo "⚠️  Could not determine mining account"
    echo "   Please set GETH_ETHEREUM_ACCOUNT or create accounts first:"
    echo "   geth account new --keystore $EXPANDED_GETH_DATA_DIR/keystore"
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

echo "Mining account: $GETH_ETHEREUM_ACCOUNT"
echo "Operator accounts to unlock: ${#UNIQUE_OPERATORS[@]}"
if [ ${#UNIQUE_OPERATORS[@]} -gt 0 ]; then
    echo "  ${UNIQUE_OPERATORS[@]}"
fi
echo ""
echo "Starting Geth..."
echo "  RPC: http://localhost:8545"
echo "  WS:  ws://localhost:8546"
echo "  Network ID: 1101"
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

# Start Geth
geth \
    --port 3000 \
    --networkid 1101 \
    --identity 'local-dev' \
    --ws --ws.addr '127.0.0.1' --ws.port '8546' --ws.origins '*' \
    --ws.api 'admin,debug,web3,eth,txpool,personal,ethash,miner,net' \
    --http --http.port '8545' --http.addr '127.0.0.1' --http.corsdomain '' \
    --http.api 'admin,debug,web3,eth,txpool,personal,ethash,miner,net' \
    --datadir="$EXPANDED_GETH_DATA_DIR" \
    --allow-insecure-unlock \
    "${UNLOCK_ARGS[@]}" \
    --password <(echo "password") \
    --miner.etherbase="$GETH_ETHEREUM_ACCOUNT" \
    --mine \
    --miner.threads=1
