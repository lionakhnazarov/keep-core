#!/bin/bash
# Script to decode revert reason from a failed transaction

set -e

cd "$(dirname "$0")/.."

BRIDGE_ADDRESS="0xc0a2ee534F004a4ec2EFA541489acBD5ff4bBA99"
WALLET_REGISTRY_ADDRESS="0xd49141e044801DEE237993deDf9684D59fafE2e6"

echo "=========================================="
echo "Decoding Revert Reason"
echo "=========================================="
echo ""

# Get first account
FIRST_ACCOUNT=$(curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_accounts","params":[],"id":1}' | \
  jq -r '.result[0]' 2>/dev/null || echo "")

if [ -z "$FIRST_ACCOUNT" ]; then
  echo "Error: Could not get account"
  exit 1
fi

echo "Sending transaction to Bridge.requestNewWallet()..."
echo "From: $FIRST_ACCOUNT"
echo "To: $BRIDGE_ADDRESS"
echo "Data: 0x72cc8c6d"
echo ""

# Send transaction
TX_HASH=$(curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_sendTransaction\",\"params\":[{\"from\":\"$FIRST_ACCOUNT\",\"to\":\"$BRIDGE_ADDRESS\",\"data\":\"0x72cc8c6d\",\"gas\":\"0x7a120\"}],\"id\":1}" | \
  jq -r '.result' 2>/dev/null || echo "")

if [ -z "$TX_HASH" ] || [ "$TX_HASH" = "null" ]; then
  ERROR=$(curl -s -X POST http://localhost:8545 \
    -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_sendTransaction\",\"params\":[{\"from\":\"$FIRST_ACCOUNT\",\"to\":\"$BRIDGE_ADDRESS\",\"data\":\"0x72cc8c6d\",\"gas\":\"0x7a120\"}],\"id\":1}" | \
    jq -r '.error' 2>/dev/null || echo "")
  echo "Transaction failed to send:"
  echo "$ERROR" | jq '.'
  exit 1
fi

echo "Transaction hash: $TX_HASH"
echo "Waiting for transaction to be mined..."
sleep 3

# Get receipt
RECEIPT=$(curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getTransactionReceipt\",\"params\":[\"$TX_HASH\"],\"id\":1}" | \
  jq -r '.result' 2>/dev/null || echo "")

if [ -z "$RECEIPT" ] || [ "$RECEIPT" = "null" ]; then
  echo "Transaction not yet mined. Check later with:"
  echo "  ./scripts/check-transaction-receipt.sh $TX_HASH"
  exit 0
fi

STATUS=$(echo "$RECEIPT" | jq -r '.status' 2>/dev/null || echo "")

if [ "$STATUS" = "0x1" ] || [ "$STATUS" = "1" ]; then
  echo "✓ Transaction succeeded!"
  exit 0
fi

echo "Transaction reverted. Attempting to decode revert reason..."
echo ""

# Try to get revert reason using debug_traceTransaction
TRACE=$(curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"debug_traceTransaction\",\"params\":[\"$TX_HASH\",{\"tracer\":\"callTracer\"}],\"id\":1}" 2>/dev/null || echo "")

if [ -n "$TRACE" ] && [ "$TRACE" != "null" ]; then
  echo "Trace result:"
  echo "$TRACE" | jq '.' 2>/dev/null || echo "$TRACE"
else
  echo "Could not get trace (debug_traceTransaction not available)"
  echo ""
  echo "The transaction reverted. Common reasons:"
  echo "  1. Bridge is not walletOwner (but we verified it is)"
  echo "  2. DKG state is not IDLE (but we verified it is)"
  echo "  3. SortitionPool is locked (but we verified it's not)"
  echo "  4. RandomBeacon authorization issue"
  echo ""
  echo "Try checking the transaction receipt for more details:"
  echo "  ./scripts/check-transaction-receipt.sh $TX_HASH"
fi

