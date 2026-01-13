#!/bin/bash
# Test deposit reveal using cast with correct tuple format

BRIDGE="0xc7BC782Da1AAb7ee5985aC94C575f374FA4C75e5"
RPC_URL="http://localhost:8545"

# Get first account from geth
ACCOUNT=$(cast rpc eth_accounts --rpc-url "$RPC_URL" 2>/dev/null | jq -r '.[0]' 2>/dev/null || echo "")

if [ -z "$ACCOUNT" ] || [ "$ACCOUNT" = "null" ]; then
  echo "❌ No accounts found. Make sure geth is running."
  exit 1
fi

# Check if deposit data exists
if [ ! -f "deposit-data/funding-tx-info.json" ] || [ ! -f "deposit-data/deposit-reveal-info.json" ]; then
  echo "❌ Deposit data files not found. Run: ./scripts/emulate-deposit.sh"
  exit 1
fi

# Extract values for tuple format
VERSION=$(cat deposit-data/funding-tx-info.json | jq -r '.version')
INPUT_VECTOR=$(cat deposit-data/funding-tx-info.json | jq -r '.inputVector')
OUTPUT_VECTOR=$(cat deposit-data/funding-tx-info.json | jq -r '.outputVector')
LOCKTIME=$(cat deposit-data/funding-tx-info.json | jq -r '.locktime')

FUNDING_OUTPUT_INDEX=$(cat deposit-data/deposit-reveal-info.json | jq -r '.fundingOutputIndex')
BLINDING_FACTOR=$(cat deposit-data/deposit-reveal-info.json | jq -r '.blindingFactor')
WALLET_PKH=$(cat deposit-data/deposit-reveal-info.json | jq -r '.walletPubKeyHash')
REFUND_PKH=$(cat deposit-data/deposit-reveal-info.json | jq -r '.refundPubKeyHash')
REFUND_LOCKTIME=$(cat deposit-data/deposit-reveal-info.json | jq -r '.refundLocktime')
VAULT=$(cat deposit-data/deposit-reveal-info.json | jq -r '.vault')

echo "=========================================="
echo "Testing Deposit Reveal with cast"
echo "=========================================="
echo "Bridge: $BRIDGE"
echo "Account: $ACCOUNT"
echo "RPC URL: $RPC_URL"
echo ""

# Format as tuple: (bytes4,bytes,bytes,bytes4) and (uint32,bytes8,bytes20,bytes20,bytes4,address)
FUNDING_TX_TUPLE="($VERSION,$INPUT_VECTOR,$OUTPUT_VECTOR,$LOCKTIME)"
REVEAL_TUPLE="($FUNDING_OUTPUT_INDEX,$BLINDING_FACTOR,$WALLET_PKH,$REFUND_PKH,$REFUND_LOCKTIME,$VAULT)"

echo "Step 1: Testing with cast estimate..."
cast estimate "$BRIDGE" \
  "revealDeposit((bytes4,bytes,bytes,bytes4),(uint32,bytes8,bytes20,bytes20,bytes4,address))" \
  "$FUNDING_TX_TUPLE" \
  "$REVEAL_TUPLE" \
  --rpc-url "$RPC_URL" \
  --from "$ACCOUNT" 2>&1

if [ $? -eq 0 ]; then
  echo ""
  echo "✅ Gas estimation successful!"
  echo ""
  echo "Step 2: To submit the transaction, run:"
  echo ""
  echo "cast send $BRIDGE \\"
  echo "  \"revealDeposit((bytes4,bytes,bytes,bytes4),(uint32,bytes8,bytes20,bytes20,bytes4,address))\" \\"
  echo "  \"$FUNDING_TX_TUPLE\" \\"
  echo "  \"$REVEAL_TUPLE\" \\"
  echo "  --rpc-url $RPC_URL \\"
  echo "  --from $ACCOUNT \\"
  echo "  --unlocked"
else
  echo ""
  echo "❌ Gas estimation failed. Trying with keep-client instead..."
  echo ""
  echo "Alternative: Use keep-client:"
  echo "./keep-client ethereum tbtc bridge reveal-deposit \\"
  echo "  --ethereum.url $RPC_URL \\"
  echo "  --submit \\"
  echo "  \"\$(cat deposit-data/funding-tx-info.json | jq -c .)\" \\"
  echo "  \"\$(cat deposit-data/deposit-reveal-info.json | jq -c .)\""
fi
echo ""
