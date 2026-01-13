#!/bin/bash
# Script to reset DKG if it has timed out
# Checks current state and calls notifyDkgTimeout() if DKG is in AWAITING_RESULT and has timed out

set -e

cd "$(dirname "$0")/.."

RPC_URL="http://localhost:8545"

# Get WalletRegistry address from deployment file
WR_DEPLOYMENT_FILE="solidity/ecdsa/deployments/development/WalletRegistry.json"
if [ -f "$WR_DEPLOYMENT_FILE" ]; then
  WR=$(jq -r '.address' "$WR_DEPLOYMENT_FILE" 2>/dev/null || echo "")
fi

# Fallback to hardcoded address if deployment file not found
if [ -z "$WR" ] || [ "$WR" = "null" ] || [ "$WR" = "" ]; then
  WR="0x64F6B5b4AeF3F69952d3B8313F33E99AaAb69241"
  echo "⚠️  Warning: Using hardcoded WalletRegistry address: $WR"
  echo "   Could not read from $WR_DEPLOYMENT_FILE"
  echo ""
else
  echo "Using WalletRegistry address from deployment: $WR"
  echo ""
fi

echo "=========================================="
echo "Reset DKG if Timed Out"
echo "=========================================="
echo ""

# Get current state
STATE_RAW=$(cast call $WR "getWalletCreationState()" --rpc-url $RPC_URL 2>&1)
if [ -z "$STATE_RAW" ] || [ "$STATE_RAW" = "" ]; then
  echo "Error: Failed to call getWalletCreationState()"
  echo "   WalletRegistry address: $WR"
  echo "   RPC URL: $RPC_URL"
  echo "   Response: $STATE_RAW"
  exit 1
fi

STATE=$(echo "$STATE_RAW" | cast --to-dec 2>/dev/null || echo "")
if [ -z "$STATE" ] || [ "$STATE" = "" ]; then
  echo "Error: Could not parse state value"
  echo "   Raw response: $STATE_RAW"
  echo "   Try: cast call $WR \"getWalletCreationState()\" --rpc-url $RPC_URL"
  exit 1
fi

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
TX_OUTPUT=$(cast send $WR "notifyDkgTimeout()" \
  --rpc-url $RPC_URL \
  --unlocked \
  --from $ACCOUNT \
  --gas-limit 300000 2>&1)

# Extract transaction hash (macOS-compatible - works with both GNU and BSD grep)
TX_HASH=$(echo "$TX_OUTPUT" | grep -oE 'transactionHash: 0x[0-9a-f]+' | sed 's/transactionHash: //' || echo "")
if [ -z "$TX_HASH" ]; then
  # Try alternative format
  TX_HASH=$(echo "$TX_OUTPUT" | grep -oE '0x[0-9a-f]{64}' | head -1 || echo "")
fi

if [ -z "$TX_HASH" ]; then
  echo "Error: Failed to get transaction hash"
  echo "   Output: $TX_OUTPUT"
  exit 1
fi

echo "Transaction submitted: $TX_HASH"
echo "Waiting for confirmation..."

# Poll for transaction receipt with timeout
MAX_ATTEMPTS=60  # 60 attempts * 1 second = 60 seconds max wait
ATTEMPT=0
STATUS=""
RECEIPT=""
FOUND_RECEIPT=false

# First, check if receipt already exists (transaction might be instant on local dev)
RECEIPT_CHECK=$(cast receipt $TX_HASH --rpc-url $RPC_URL 2>&1)
if echo "$RECEIPT_CHECK" | grep -qE '(status|blockNumber)'; then
  RECEIPT="$RECEIPT_CHECK"
  STATUS=$(echo "$RECEIPT" | grep -E 'status' | grep -oE '[0-9]+' | head -1 || echo "")
  if [ -n "$STATUS" ] && [ "$STATUS" != "" ]; then
    FOUND_RECEIPT=true
    echo "✓ Transaction already confirmed!"
  fi
fi

# If not found, check if transaction exists in mempool
if [ "$FOUND_RECEIPT" != "true" ]; then
  TX_EXISTS=$(cast tx $TX_HASH --rpc-url $RPC_URL 2>/dev/null | head -1 || echo "")
  if [ -z "$TX_EXISTS" ] || [ "$TX_EXISTS" = "" ]; then
    echo "⚠️  Transaction not found in mempool - checking if already mined..."
    # Give it one more check for receipt
    sleep 1
    RECEIPT_CHECK=$(cast receipt $TX_HASH --rpc-url $RPC_URL 2>&1)
    if echo "$RECEIPT_CHECK" | grep -qE '(status|blockNumber)'; then
      RECEIPT="$RECEIPT_CHECK"
      STATUS=$(echo "$RECEIPT" | grep -E 'status' | grep -oE '[0-9]+' | head -1 || echo "")
      if [ -n "$STATUS" ] && [ "$STATUS" != "" ]; then
        FOUND_RECEIPT=true
        echo "✓ Transaction was already mined!"
      fi
    fi
  fi
fi

# Poll for receipt if not already found
if [ "$FOUND_RECEIPT" != "true" ]; then
  while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    # Try to get receipt
    RECEIPT_OUTPUT=$(cast receipt $TX_HASH --rpc-url $RPC_URL 2>&1)
    RECEIPT_EXIT_CODE=$?
    
    if [ $RECEIPT_EXIT_CODE -eq 0 ] && [ -n "$RECEIPT_OUTPUT" ]; then
      # Check if receipt contains status or blockNumber (indicates it's a valid receipt)
      if echo "$RECEIPT_OUTPUT" | grep -qE '(status|blockNumber)'; then
        # Try to extract status
        STATUS=$(echo "$RECEIPT_OUTPUT" | grep -E 'status' | grep -oE '[0-9]+' | head -1 || echo "")
        if [ -n "$STATUS" ] && [ "$STATUS" != "" ]; then
          RECEIPT="$RECEIPT_OUTPUT"
          FOUND_RECEIPT=true
          break
        fi
      fi
    fi
    
    ATTEMPT=$((ATTEMPT + 1))
    # Show progress every 5 seconds
    if [ $((ATTEMPT % 5)) -eq 0 ]; then
      echo "  Still waiting... ($ATTEMPT/$MAX_ATTEMPTS seconds)"
    else
      # Show a dot for visual feedback
      echo -n "."
    fi
    sleep 1
  done
fi

echo ""  # New line after dots

if [ "$FOUND_RECEIPT" != "true" ] || [ -z "$STATUS" ] || [ "$STATUS" = "" ]; then
  echo ""
  echo "⚠️  Transaction receipt not found after $MAX_ATTEMPTS seconds"
  echo "   Transaction hash: $TX_HASH"
  echo ""
  echo "   Troubleshooting:"
  echo "   1. Check if transaction exists: cast tx $TX_HASH --rpc-url $RPC_URL"
  echo "   2. Check receipt manually: cast receipt $TX_HASH --rpc-url $RPC_URL"
  echo "   3. Check if node is synced: cast block-number --rpc-url $RPC_URL"
  echo "   4. Transaction may still be pending - check again later"
  echo ""
  exit 1
fi

if [ "$STATUS" = "1" ]; then
  echo "✓ Transaction successful!"
  echo ""
  
  # Get block number from receipt
  BLOCK_NUM=$(echo "$RECEIPT" | grep -E 'blockNumber' | grep -oE '[0-9]+' | head -1 || echo "unknown")
  echo "   Confirmed in block: $BLOCK_NUM"
  echo ""
  
  # Verify state
  NEW_STATE_RAW=$(cast call $WR "getWalletCreationState()" --rpc-url $RPC_URL 2>&1)
  NEW_STATE=$(echo "$NEW_STATE_RAW" | cast --to-dec 2>/dev/null || echo "")
  if [ -z "$NEW_STATE" ]; then
    echo "⚠️  Could not parse new state (raw: $NEW_STATE_RAW)"
    NEW_STATE="unknown"
  fi
  
  if [ "$NEW_STATE" = "0" ]; then
    echo "✓ DKG successfully reset to IDLE state"
  else
    echo "⚠️  DKG state is now $NEW_STATE (expected 0)"
  fi
elif [ "$STATUS" = "0" ]; then
  echo "✗ Transaction failed (status: 0)"
  echo "   Transaction hash: $TX_HASH"
  echo "   Check receipt for revert reason: cast receipt $TX_HASH --rpc-url $RPC_URL"
  exit 1
else
  echo "✗ Unknown transaction status: $STATUS"
  echo "   Transaction hash: $TX_HASH"
  echo "   Receipt: $RECEIPT"
  exit 1
fi
