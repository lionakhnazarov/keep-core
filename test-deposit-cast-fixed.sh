#!/bin/bash
# Test deposit reveal using cast (fixed format)

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

# Format arguments for cast (cast expects tuple format)
FUNDING_TX=$(cat deposit-data/funding-tx-info.json | jq -c '{version: .version, inputVector: .inputVector, outputVector: .outputVector, locktime: .locktime}')
REVEAL_INFO=$(cat deposit-data/deposit-reveal-info.json | jq -c '{fundingOutputIndex: .fundingOutputIndex, blindingFactor: .blindingFactor, walletPubKeyHash: .walletPubKeyHash, refundPubKeyHash: .refundPubKeyHash, refundLocktime: .refundLocktime, vault: .vault}')

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

if [ $? -eq 0 ]; then
  echo ""
  echo "✅ Gas estimation successful!"
  echo ""
  echo "Step 2: To submit the transaction, run:"
  echo ""
  echo "cast send $BRIDGE \\"
  echo "  \"revealDeposit((bytes4,bytes,bytes,bytes4),(uint32,bytes8,bytes20,bytes20,bytes4,address))\" \\"
  echo "  '$FUNDING_TX' \\"
  echo "  '$REVEAL_INFO' \\"
  echo "  --rpc-url $RPC_URL \\"
  echo "  --from $ACCOUNT \\"
  echo "  --unlocked"
else
  echo ""
  echo "❌ Gas estimation failed. Check the error above."
fi
echo ""
