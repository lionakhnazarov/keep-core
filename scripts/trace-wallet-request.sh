#!/bin/bash
# Script to send transaction and trace it to see why it's reverting

set -e

cd "$(dirname "$0")/.."

BRIDGE_ADDRESS="0xc0a2ee534F004a4ec2EFA541489acBD5ff4bBA99"
WALLET_REGISTRY_ADDRESS="0xd49141e044801DEE237993deDf9684D59fafE2e6"

echo "=========================================="
echo "Tracing Wallet Request Transaction"
echo "=========================================="
echo ""

# Get first account
FIRST_ACCOUNT=$(curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_accounts","params":[],"id":1}' | \
  jq -r '.result[0]' 2>/dev/null || echo "")

if [ -z "$FIRST_ACCOUNT" ]; then
  echo "Error: Could not get account from Geth"
  exit 1
fi

echo "Using account: $FIRST_ACCOUNT"
echo "Bridge: $BRIDGE_ADDRESS"
echo "WalletRegistry: $WALLET_REGISTRY_ADDRESS"
echo ""

# Unlock account
echo "Unlocking account..."
curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"personal_unlockAccount\",\"params\":[\"$FIRST_ACCOUNT\",\"\",0],\"id\":1}" > /dev/null

# Send transaction
echo "Sending transaction..."
TX_HASH=$(curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_sendTransaction\",\"params\":[{\"from\":\"$FIRST_ACCOUNT\",\"to\":\"$BRIDGE_ADDRESS\",\"data\":\"0x72cc8c6d\",\"gas\":\"0x7a120\"}],\"id\":1}" | \
  jq -r '.result' 2>/dev/null || echo "")

if [ -z "$TX_HASH" ] || [ "$TX_HASH" = "null" ]; then
  echo "Error: Transaction failed to send"
  exit 1
fi

echo "Transaction hash: $TX_HASH"
echo "Waiting for transaction to be mined..."

# Wait for transaction
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
BLOCK_NUMBER=$(echo "$RECEIPT" | jq -r '.blockNumber' 2>/dev/null || echo "")

echo "Block: $BLOCK_NUMBER"
echo "Status: $STATUS"

if [ "$STATUS" = "0x0" ] || [ "$STATUS" = "0" ]; then
  echo ""
  echo "Transaction reverted. Attempting to trace..."
  
  # Try to get trace
  TRACE=$(curl -s -X POST http://localhost:8545 \
    -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"debug_traceTransaction\",\"params\":[\"$TX_HASH\",{\"tracer\":\"callTracer\"}],\"id\":1}" 2>/dev/null || echo "")
  
  if [ -n "$TRACE" ] && [ "$TRACE" != "null" ]; then
    echo "$TRACE" | jq '.' 2>/dev/null || echo "$TRACE"
  else
    echo "Could not get trace (debug_traceTransaction not available)"
    echo ""
    echo "Check receipt details:"
    echo "  ./scripts/check-transaction-receipt.sh $TX_HASH"
  fi
else
  echo "✓ Transaction succeeded!"
fi

