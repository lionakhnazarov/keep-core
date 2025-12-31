#!/bin/bash
# Script to reset DKG if it has timed out
# Checks current state and calls notifyDkgTimeout() if DKG is in AWAITING_RESULT and has timed out

set -e

cd "$(dirname "$0")/.."

WR="0x64F6B5b4AeF3F69952d3B8313F33E99AaAb69241"
RPC_URL="http://localhost:8545"

echo "=========================================="
echo "Reset DKG if Timed Out"
echo "=========================================="
echo ""

# Get current state
STATE=$(cast call $WR "getWalletCreationState()" --rpc-url $RPC_URL | cast --to-dec)
echo "Current DKG State: $STATE"
echo "  (0=IDLE, 1=AWAITING_SEED, 2=AWAITING_RESULT, 3=CHALLENGE)"
echo ""

if [ "$STATE" = "0" ]; then
  echo "✓ DKG is already IDLE - no reset needed"
  exit 0
fi

if [ "$STATE" != "2" ]; then
  echo "⚠️  DKG is in state $STATE (not AWAITING_RESULT)"
  echo "   notifyDkgTimeout() only works when state is 2 (AWAITING_RESULT)"
  exit 1
fi

# Check if DKG has timed out
TIMED_OUT=$(cast call $WR "hasDkgTimedOut()" --rpc-url $RPC_URL)
if [ "$TIMED_OUT" != "0x0000000000000000000000000000000000000000000000000000000000000001" ]; then
  echo "⚠️  DKG has not timed out yet"
  echo "   Cannot reset DKG until timeout period has passed"
  echo ""
  echo "   Check timeout status:"
  echo "   cast call $WR \"hasDkgTimedOut()\" --rpc-url $RPC_URL"
  exit 1
fi

echo "✓ DKG has timed out - resetting to IDLE..."
echo ""

# Get account
ACCOUNT=$(cast rpc eth_accounts --rpc-url $RPC_URL | jq -r '.[0]')
if [ -z "$ACCOUNT" ]; then
  echo "Error: No accounts available"
  exit 1
fi

# Call notifyDkgTimeout()
echo "Calling notifyDkgTimeout()..."
TX_HASH=$(cast send $WR "notifyDkgTimeout()" \
  --rpc-url $RPC_URL \
  --unlocked \
  --from $ACCOUNT \
  --gas-limit 300000 2>&1 | grep -oP 'transactionHash: \K[0-9a-fx]+' || echo "")

if [ -z "$TX_HASH" ]; then
  echo "Error: Failed to get transaction hash"
  exit 1
fi

echo "Transaction submitted: $TX_HASH"
echo "Waiting for confirmation..."

sleep 3

# Check transaction status
STATUS=$(cast receipt $TX_HASH --rpc-url $RPC_URL 2>/dev/null | grep -oP 'status\s+\K[0-9]+' || echo "")
if [ "$STATUS" = "1" ]; then
  echo "✓ Transaction successful!"
  echo ""
  
  # Verify state
  NEW_STATE=$(cast call $WR "getWalletCreationState()" --rpc-url $RPC_URL | cast --to-dec)
  if [ "$NEW_STATE" = "0" ]; then
    echo "✓ DKG successfully reset to IDLE state"
  else
    echo "⚠️  DKG state is now $NEW_STATE (expected 0)"
  fi
else
  echo "✗ Transaction failed or pending"
  echo "   Check receipt: cast receipt $TX_HASH --rpc-url $RPC_URL"
  exit 1
fi
