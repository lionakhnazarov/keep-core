#!/bin/bash
# Complete setup script for mock Bitcoin chain to enable deposit sweeps
# This script:
# 1. Sets up Bitcoin regtest node
# 2. Creates a funding transaction matching the deposit reveal
# 3. Configures nodes to use the regtest node

set -e

cd "$(dirname "$0")/.."

PROJECT_ROOT="$(pwd)"
RPC_URL="http://localhost:8545"
BRIDGE="0xc7BC782Da1AAb7ee5985aC94C575f374FA4C75e5"

echo "=========================================="
echo "Mock Bitcoin Chain Setup for Deposit Sweeps"
echo "=========================================="
echo ""

# Step 1: Check if deposit exists
echo "Step 1: Checking for revealed deposits..."
EVENT_DATA=$(cast logs --from-block 0 --to-block latest --address $BRIDGE --rpc-url $RPC_URL --json 2>/dev/null | \
  jq -r '.[] | select(.topics[0] == "0xa7382159a693ed317a024daf0fd1ba30805cdf9928ee09550af517c516e2ef05") | .data' | head -1)

if [ -z "$EVENT_DATA" ] || [ "$EVENT_DATA" == "null" ]; then
  echo "⚠️  No DepositRevealed event found"
  echo "   Please reveal a deposit first using reveal-deposit.sh"
  exit 1
fi

echo "✅ Deposit found"
echo ""

# Step 2: Extract funding transaction info
echo "Step 2: Extracting funding transaction information..."
FUNDING_TX_HASH_HEX="${EVENT_DATA:2:64}"
echo "Funding TX Hash (Ethereum format): 0x$FUNDING_TX_HASH_HEX"
echo ""

# Step 3: Check Bitcoin Core
echo "Step 3: Checking Bitcoin Core installation..."
if ! command -v bitcoind &> /dev/null; then
  echo "❌ Bitcoin Core not found"
  echo ""
  echo "Install Bitcoin Core:"
  echo "  macOS: brew install bitcoin"
  echo "  Linux: sudo apt-get install bitcoin"
  exit 1
fi

echo "✅ Bitcoin Core found"
echo ""

# Step 4: Setup regtest node
echo "Step 4: Setting up Bitcoin regtest node..."
BITCOIN_DATA_DIR="$PROJECT_ROOT/bitcoin-regtest"
mkdir -p "$BITCOIN_DATA_DIR"

BITCOIN_CLI="bitcoin-cli -regtest -datadir=$BITCOIN_DATA_DIR -rpcuser=testuser -rpcpassword=testpass"

# Stop existing node if running
if pgrep -f "bitcoind.*regtest.*$BITCOIN_DATA_DIR" > /dev/null; then
  echo "Stopping existing regtest node..."
  $BITCOIN_CLI stop > /dev/null 2>&1 || pkill -f "bitcoind.*regtest.*$BITCOIN_DATA_DIR" || true
  sleep 2
fi

# Start regtest node
echo "Starting regtest node..."
bitcoind \
  -regtest \
  -datadir="$BITCOIN_DATA_DIR" \
  -server \
  -rpcuser=testuser \
  -rpcpassword=testpass \
  -rpcport=18443 \
  -port=18444 \
  -txindex=1 \
  -daemon

sleep 3

if ! $BITCOIN_CLI getblockchaininfo > /dev/null 2>&1; then
  echo "❌ Failed to start Bitcoin regtest node"
  exit 1
fi

echo "✅ Regtest node started"
echo ""

# Step 5: Generate initial blocks
echo "Step 5: Generating initial blocks..."
$BITCOIN_CLI generate 101 > /dev/null 2>&1 || {
  echo "⚠️  Warning: Could not generate blocks immediately"
  echo "   Node may still be starting. Waiting..."
  sleep 5
  $BITCOIN_CLI generate 101 > /dev/null 2>&1 || {
    echo "❌ Failed to generate blocks"
    exit 1
  }
}

echo "✅ Initial blocks generated"
echo ""

# Step 6: Important note about transaction hashes
echo "=========================================="
echo "Important: Transaction Hash Mismatch"
echo "=========================================="
echo ""
echo "⚠️  CRITICAL ISSUE:"
echo ""
echo "The funding transaction hash in your deposit reveal (0x$FUNDING_TX_HASH_HEX)"
echo "was randomly generated and doesn't correspond to a real Bitcoin transaction."
echo ""
echo "Bitcoin transaction hashes are deterministic - they're calculated from the"
echo "transaction content. You cannot create a transaction with a specific hash."
echo ""
echo "SOLUTIONS:"
echo ""
echo "Option 1: Use a Mock Electrum Server (Recommended for Testing)"
echo "  - Create a mock Electrum server that returns transaction data"
echo "  - Configure nodes to use the mock server"
echo "  - The mock server can return any transaction data you want"
echo ""
echo "Option 2: Re-create Deposit with Real Transaction"
echo "  - Create Bitcoin transaction FIRST on regtest"
echo "  - Get its hash"
echo "  - Use that hash when revealing the deposit"
echo ""
echo "Option 3: Modify Bridge Contract (Testing Only)"
echo "  - Temporarily disable Bitcoin TX verification in Bridge"
echo "  - Only for local testing, never in production"
echo ""
echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "To proceed with Option 1 (Mock Electrum Server):"
echo "  1. Create a mock Electrum server (see scripts/create-mock-electrum-server.go)"
echo "  2. Update config.toml to point to localhost mock server"
echo "  3. Restart nodes"
echo ""
echo "Bitcoin regtest node is running:"
echo "  RPC: http://testuser:testpass@localhost:18443"
echo "  Data: $BITCOIN_DATA_DIR"
echo ""
echo "To stop: $BITCOIN_CLI stop"
echo ""

