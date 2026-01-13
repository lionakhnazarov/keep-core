#!/bin/bash
# Test deposit reveal using cast

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

# Prepare JSON arguments
FUNDING_TX=$(cat deposit-data/funding-tx-info.json | jq -c .)
REVEAL_INFO=$(cat deposit-data/deposit-reveal-info.json | jq -c .)

echo "=========================================="
echo "Testing Deposit Reveal with cast"
echo "=========================================="
echo "Bridge: $BRIDGE"
echo "Account: $ACCOUNT"
echo "RPC URL: $RPC_URL"
echo ""

# First, estimate gas (dry-run)
echo "Step 1: Estimating gas..."
cast estimate "$BRIDGE" \
  "revealDeposit((bytes4,bytes,bytes,bytes4),(uint32,bytes8,bytes20,bytes20,bytes4,address))" \
  "$FUNDING_TX" \
  "$REVEAL_INFO" \
  --rpc-url "$RPC_URL" \
  --from "$ACCOUNT" 2>&1

echo ""
echo "Step 2: To submit the transaction, run:"
echo ""
echo "cast send $BRIDGE \\"
echo "  \"revealDeposit((bytes4,bytes,bytes,bytes4),(uint32,bytes8,bytes20,bytes20,bytes4,address))\" \\"
echo "  \"$FUNDING_TX\" \\"
echo "  \"$REVEAL_INFO\" \\"
echo "  --rpc-url $RPC_URL \\"
echo "  --from $ACCOUNT \\"
echo "  --unlocked"
echo ""
