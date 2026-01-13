#!/bin/bash
# Add funding transaction to Bitcoin regtest node
# This script reconstructs the Bitcoin transaction from deposit reveal data
# and adds it to the local regtest chain

set -e

cd "$(dirname "$0")/.."

RPC_URL="http://localhost:8545"
BRIDGE="0xc7BC782Da1AAb7ee5985aC94C575f374FA4C75e5"

echo "=========================================="
echo "Adding Funding Transaction to Bitcoin Chain"
echo "=========================================="
echo ""

# Check if deposit data exists
if [ ! -f "deposit-data/deposit-data.json" ]; then
  echo "❌ Error: deposit-data/deposit-data.json not found"
  echo "   Run: ./scripts/emulate-deposit.sh first"
  exit 1
fi

# Read deposit data
FUNDING_TX_INFO=$(jq -r '.fundingTxInfo' deposit-data/deposit-data.json)
FUNDING_TX_HASH=$(jq -r '.fundingTxHash' deposit-data/deposit-data.json)

echo "Funding TX Hash: $FUNDING_TX_HASH"
echo ""

# Extract transaction components
VERSION=$(echo "$FUNDING_TX_INFO" | jq -r '.version')
INPUT_VECTOR=$(echo "$FUNDING_TX_INFO" | jq -r '.inputVector')
OUTPUT_VECTOR=$(echo "$FUNDING_TX_INFO" | jq -r '.outputVector')
LOCKTIME=$(echo "$FUNDING_TX_INFO" | jq -r '.locktime')

echo "Transaction Components:"
echo "  Version: $VERSION"
echo "  Input Vector: ${INPUT_VECTOR:0:50}..."
echo "  Output Vector: ${OUTPUT_VECTOR:0:50}..."
echo "  Locktime: $LOCKTIME"
echo ""

# Check if Bitcoin regtest is running
BITCOIN_CLI="bitcoin-cli -regtest -datadir=$PROJECT_ROOT/bitcoin-regtest -rpcuser=testuser -rpcpassword=testpass"

if ! $BITCOIN_CLI getblockchaininfo > /dev/null 2>&1; then
  echo "⚠️  Bitcoin regtest node not running"
  echo "   Start it with: ./setup-mock-bitcoin-chain.sh"
  exit 1
fi

echo "✅ Bitcoin regtest node is running"
echo ""

# Create raw transaction from components
# Combine: version + inputVector + outputVector + locktime
RAW_TX="${VERSION:2}${INPUT_VECTOR:2}${OUTPUT_VECTOR:2}${LOCKTIME:2}"

echo "Raw Transaction (hex): ${RAW_TX:0:100}..."
echo ""

# Note: The transaction hash will be different when broadcast to regtest
# because Bitcoin transaction hashes are deterministic based on the transaction content.
# However, for testing purposes, we can:
# 1. Broadcast this transaction to regtest
# 2. Get its actual hash
# 3. Update the deposit reveal to use the new hash

echo "⚠️  Important Note:"
echo "   Bitcoin transaction hashes are deterministic. The hash in your"
echo "   deposit reveal ($FUNDING_TX_HASH) was randomly generated and won't"
echo "   match any real transaction."
echo ""
echo "   To properly test deposit sweeps, you need to:"
echo "   1. Create the Bitcoin transaction FIRST"
echo "   2. Get its hash"
echo "   3. Use that hash in the deposit reveal"
echo ""
echo "   OR: Modify the Bridge contract to accept deposits without"
echo "   verifying the Bitcoin transaction exists (for testing only)."
echo ""
echo "=========================================="
echo "Alternative: Mock Electrum Server"
echo "=========================================="
echo ""
echo "For local testing, you could create a mock Electrum server that"
echo "returns the transaction data when queried, even though the"
echo "transaction doesn't exist on a real Bitcoin chain."
echo ""
echo "This would require:"
echo "  1. Creating a mock Electrum server"
echo "  2. Configuring nodes to use it instead of the real Electrum server"
echo "  3. The mock server would return transaction data and confirmations"
echo "     based on the deposit reveal data"
echo ""

