#!/bin/bash
# Script to check for RedemptionRequested events from Bridge contract

set -e

cd "$(dirname "$0")/.."

# Get Bridge address from deployment file
BRIDGE_DEPLOYMENT_FILE="solidity/tbtc-stub/deployments/development/Bridge.json"
if [ -f "$BRIDGE_DEPLOYMENT_FILE" ]; then
  BRIDGE_ADDRESS=$(jq -r '.address' "$BRIDGE_DEPLOYMENT_FILE" 2>/dev/null || echo "")
fi
BRIDGE="${BRIDGE_ADDRESS:-0xE050D7EA1Bb14278cBFCa591EaA887e48C9BdE08}"

RPC_URL="${RPC_URL:-http://localhost:8545}"

echo "=========================================="
echo "Checking RedemptionRequested Events"
echo "=========================================="
echo ""
echo "Bridge: $BRIDGE"
echo "RPC: $RPC_URL"
echo ""

# Get current block number
CURRENT_BLOCK=$(cast block-number --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
echo "Current block: $CURRENT_BLOCK"
echo ""

# Check events from last 1000 blocks
FROM_BLOCK=$((CURRENT_BLOCK > 1000 ? CURRENT_BLOCK - 1000 : 0))
echo "Checking events from block $FROM_BLOCK to latest..."
echo ""

# Query for RedemptionRequested events
EVENT_SIG="RedemptionRequested(bytes20,bytes,address,uint64,uint64,uint64,uint32)"
EVENTS=$(cast logs --from-block $FROM_BLOCK --to-block latest --address "$BRIDGE" "$EVENT_SIG" --rpc-url "$RPC_URL" 2>&1)

if echo "$EVENTS" | jq -e '. | length > 0' >/dev/null 2>&1; then
  EVENT_COUNT=$(echo "$EVENTS" | jq -r 'length')
  echo "✓ Found $EVENT_COUNT RedemptionRequested event(s):"
  echo ""
  
  echo "$EVENTS" | jq -r '.[] | "
Event #\(.logIndex // .transactionIndex):
  Block: \(.blockNumber)
  Transaction: \(.transactionHash)
  Wallet PKH: \(.topics[1])
  Redeemer: \(.topics[2])
  Data: \(.data)
"'
  
  echo ""
  echo "Full event details:"
  echo "$EVENTS" | jq '.'
else
  echo "✗ No RedemptionRequested events found"
  echo ""
  echo "This could mean:"
  echo "  1. No redemption requests have been submitted"
  echo "  2. Events were emitted before block $FROM_BLOCK"
  echo "  3. Events were emitted to a different Bridge address"
  echo ""
  echo "To check all blocks, use:"
  echo "  cast logs --from-block 0 --to-block latest --address $BRIDGE \"$EVENT_SIG\" --rpc-url $RPC_URL"
fi

echo ""
echo "=========================================="
echo "Checking Pending Redemptions (Storage)"
echo "=========================================="
echo ""

# Check if there are any pending redemptions stored (requires knowing redemption keys)
# This is a placeholder - you'd need to know the wallet PKH and output script
echo "To check a specific pending redemption, use:"
echo "  REDEMPTION_KEY=\$(cast keccak \"<walletPKH><outputScript>\")"
echo "  cast call $BRIDGE \"getPendingRedemption(uint256)\" \$REDEMPTION_KEY --rpc-url $RPC_URL"
echo ""
echo "Example for wallet 0x9850b965a0ef404ce03dd88691201cc537beaefd:"
REDEMPTION_KEY=$(cast keccak "0x9850b965a0ef404ce03dd88691201cc537beaefd76a914000000000000000000000000000000000000000188ac" 2>/dev/null || echo "")
if [ -n "$REDEMPTION_KEY" ]; then
  PENDING_DATA=$(cast call "$BRIDGE" "getPendingRedemption(uint256)" "$REDEMPTION_KEY" --rpc-url "$RPC_URL" 2>&1 || echo "")
  if echo "$PENDING_DATA" | grep -q "0x0000000000000000000000000000000000000000000000000000000000000000"; then
    echo "  ✗ No pending redemption found"
  else
    echo "  ✓ Pending redemption exists (but no event was emitted)"
    echo "    Data: $PENDING_DATA"
  fi
fi
