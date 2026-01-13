#!/bin/bash
# Setup mock Bitcoin chain for deposit sweep testing
# This script creates a local Bitcoin regtest node and configures it

set -e

cd "$(dirname "$0")/.."

echo "=========================================="
echo "Setting up Mock Bitcoin Chain"
echo "=========================================="
echo ""

# Check if Bitcoin Core is installed
if ! command -v bitcoind &> /dev/null && ! command -v bitcoin-cli &> /dev/null; then
  echo "⚠️  Bitcoin Core not found. Installing instructions:"
  echo ""
  echo "macOS:"
  echo "  brew install bitcoin"
  echo ""
  echo "Linux:"
  echo "  sudo apt-get install bitcoin"
  echo ""
  echo "Or download from: https://bitcoin.org/en/download"
  exit 1
fi

echo "✅ Bitcoin Core found"
echo ""

# Create Bitcoin data directory
BITCOIN_DATA_DIR="$PROJECT_ROOT/bitcoin-regtest"
mkdir -p "$BITCOIN_DATA_DIR"

echo "Bitcoin regtest data directory: $BITCOIN_DATA_DIR"
echo ""

# Check if bitcoind is already running
if pgrep -f "bitcoind.*regtest" > /dev/null; then
  echo "⚠️  Bitcoin regtest node already running"
  echo "   Stopping existing node..."
  pkill -f "bitcoind.*regtest" || true
  sleep 2
fi

echo "Starting Bitcoin regtest node..."
echo ""

# Start bitcoind in regtest mode
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

# Check if it started
if ! pgrep -f "bitcoind.*regtest" > /dev/null; then
  echo "❌ Failed to start Bitcoin regtest node"
  exit 1
fi

echo "✅ Bitcoin regtest node started"
echo ""

# Set up bitcoin-cli alias
BITCOIN_CLI="bitcoin-cli -regtest -datadir=$BITCOIN_DATA_DIR -rpcuser=testuser -rpcpassword=testpass"

# Generate initial blocks to have some coins
echo "Generating initial blocks..."
$BITCOIN_CLI generate 101 > /dev/null 2>&1 || {
  echo "⚠️  Warning: Could not generate blocks (node may still be starting)"
  echo "   Run manually: $BITCOIN_CLI generate 101"
}

echo "✅ Initial blocks generated"
echo ""

# Get the funding transaction hash from the deposit reveal
echo "Extracting deposit information..."
RPC_URL="http://localhost:8545"
BRIDGE="0xc7BC782Da1AAb7ee5985aC94C575f374FA4C75e5"

EVENT_DATA=$(cast logs --from-block 0 --to-block latest --address $BRIDGE --rpc-url $RPC_URL --json 2>/dev/null | \
  jq -r '.[] | select(.topics[0] == "0xa7382159a693ed317a024daf0fd1ba30805cdf9928ee09550af517c516e2ef05") | .data' | head -1)

if [ -z "$EVENT_DATA" ] || [ "$EVENT_DATA" == "null" ]; then
  echo "⚠️  No DepositRevealed event found"
  echo "   You need to reveal a deposit first using reveal-deposit.sh"
  echo ""
  echo "The mock Bitcoin chain is ready. When you reveal a deposit,"
  echo "you'll need to create a Bitcoin transaction matching the funding TX hash."
  exit 0
fi

# Extract funding TX hash (first 32 bytes of data, reversed for Bitcoin)
FUNDING_TX_HASH_HEX="${EVENT_DATA:2:64}"
# Reverse bytes for Bitcoin (little-endian)
FUNDING_TX_HASH_BTC=$(echo "$FUNDING_TX_HASH_HEX" | sed 's/\(..\)/\1\n/g' | tac | tr -d '\n')

echo "Funding TX Hash (Ethereum format): 0x$FUNDING_TX_HASH_HEX"
echo "Funding TX Hash (Bitcoin format): $FUNDING_TX_HASH_BTC"
echo ""

echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "The Bitcoin regtest node is running, but the funding transaction"
echo "from your deposit reveal doesn't exist yet."
echo ""
echo "To complete the setup:"
echo ""
echo "1. Create a Bitcoin transaction that matches the funding TX hash"
echo "   This is complex because Bitcoin TX hashes are deterministic."
echo ""
echo "2. OR: Use a different approach - create the Bitcoin transaction FIRST,"
echo "   then use its hash in the deposit reveal."
echo ""
echo "3. OR: For testing, modify the deposit reveal to use a transaction"
echo "   hash that you can create on regtest."
echo ""
echo "Bitcoin regtest node info:"
echo "  RPC URL: http://testuser:testpass@localhost:18443"
echo "  Data dir: $BITCOIN_DATA_DIR"
echo ""
echo "To stop the node:"
echo "  $BITCOIN_CLI stop"
echo ""
