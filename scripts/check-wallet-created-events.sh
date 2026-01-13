#!/bin/bash
# Script to check if WalletCreated events were emitted from WalletRegistry
#
# Usage:
#   ./scripts/check-wallet-created-events.sh [from-block] [to-block]
#
# Arguments:
#   from-block  Starting block number (default: 0)
#   to-block    Ending block number (default: latest)
#
# Examples:
#   ./scripts/check-wallet-created-events.sh
#   ./scripts/check-wallet-created-events.sh 1000 latest
#   ./scripts/check-wallet-created-events.sh 0 5000

set -e

cd "$(dirname "$0")/.."

PROJECT_ROOT="$(pwd)"
RPC_URL="${RPC_URL:-http://localhost:8545}"

# Get WalletRegistry address from deployment
WR=$(jq -r '.address' "$PROJECT_ROOT/solidity/ecdsa/deployments/development/WalletRegistry.json" 2>/dev/null || echo "")

if [ -z "$WR" ] || [ "$WR" = "null" ]; then
  echo "❌ Error: WalletRegistry contract not found"
  echo "   Make sure contracts are deployed: ./scripts/complete-reset.sh"
  exit 1
fi

# Parse arguments
FROM_BLOCK="${1:-0}"
TO_BLOCK="${2:-latest}"

# If from-block is a number, convert to decimal if needed
if [ "$FROM_BLOCK" != "0" ] && [ "$FROM_BLOCK" != "latest" ]; then
  FROM_BLOCK=$(cast --to-dec "$FROM_BLOCK" 2>/dev/null || echo "$FROM_BLOCK")
fi

echo "=========================================="
echo "Checking WalletCreated Events"
echo "=========================================="
echo ""
echo "WalletRegistry: $WR"
echo "RPC URL: $RPC_URL"
echo "From Block: $FROM_BLOCK"
echo "To Block: $TO_BLOCK"
echo ""

# Get current block number for reference
CURRENT_BLOCK=$(cast block-number --rpc-url "$RPC_URL" 2>/dev/null || echo "unknown")
echo "Current Block: $CURRENT_BLOCK"
echo ""

# Query for WalletCreated events
# Event signature: WalletCreated(bytes32 indexed walletID, bytes32 indexed dkgResultHash)
echo "Querying for WalletCreated events..."
WALLET_EVENTS_JSON=$(cast logs --from-block "$FROM_BLOCK" --to-block "$TO_BLOCK" \
  --address "$WR" \
  "WalletCreated(bytes32,bytes32)" \
  --rpc-url "$RPC_URL" \
  --json 2>/dev/null || echo "[]")

if [ -z "$WALLET_EVENTS_JSON" ] || [ "$WALLET_EVENTS_JSON" = "[]" ]; then
  echo "⚠️  No WalletCreated events found in the specified block range."
  echo ""
  echo "To create a wallet, run:"
  echo "  ./scripts/request-new-wallet.sh"
  exit 0
fi

# Parse JSON output from cast logs
WALLET_COUNT=$(echo "$WALLET_EVENTS_JSON" | jq -r 'length' 2>/dev/null || echo "0")

if [ "$WALLET_COUNT" = "0" ] || [ "$WALLET_COUNT" = "null" ]; then
  echo "⚠️  No WalletCreated events found."
  exit 0
fi

echo "✓ Found $WALLET_COUNT WalletCreated event(s):"
echo ""

# Process events
INDEX=0
while [ $INDEX -lt "$WALLET_COUNT" ]; do
  event=$(echo "$WALLET_EVENTS_JSON" | jq -c ".[$INDEX]")
  
  # Extract event data
  wallet_id=$(echo "$event" | jq -r '.topics[1]')
  dkg_result_hash=$(echo "$event" | jq -r '.topics[2]')
  block_number_hex=$(echo "$event" | jq -r '.blockNumber')
  block_number=$(printf "%d" "$block_number_hex" 2>/dev/null || echo "$block_number_hex")
  tx_hash=$(echo "$event" | jq -r '.transactionHash')
  
  echo "[$((INDEX + 1))] WalletCreated Event:"
  echo "    Wallet ID:      $wallet_id"
  echo "    DKG Result Hash: $dkg_result_hash"
  echo "    Block Number:   $block_number"
  echo "    Transaction:    $tx_hash"
  echo ""
  
  INDEX=$((INDEX + 1))
done

echo "=========================================="
echo "Summary: $WALLET_COUNT WalletCreated event(s) found"
echo "=========================================="


