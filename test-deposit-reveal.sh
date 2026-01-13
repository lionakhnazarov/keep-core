#!/bin/bash
# Test deposit reveal using keep-client

BRIDGE="0xc7BC782Da1AAb7ee5985aC94C575f374FA4C75e5"
RPC_URL="http://localhost:8545"

# Check if deposit data exists
if [ ! -f "deposit-data/funding-tx-info.json" ] || [ ! -f "deposit-data/deposit-reveal-info.json" ]; then
  echo "❌ Deposit data files not found. Run: ./scripts/emulate-deposit.sh"
  exit 1
fi

# Prepare JSON arguments
FUNDING_TX=$(cat deposit-data/funding-tx-info.json | jq -c .)
REVEAL_INFO=$(cat deposit-data/deposit-reveal-info.json | jq -c .)

echo "=========================================="
echo "Testing Deposit Reveal"
echo "=========================================="
echo "Bridge: $BRIDGE"
echo "RPC URL: $RPC_URL"
echo ""

# First, test with a call (dry-run)
echo "Step 1: Testing revealDeposit call (dry-run)..."
./keep-client ethereum tbtc bridge reveal-deposit \
  --ethereum.url "$RPC_URL" \
  "$FUNDING_TX" \
  "$REVEAL_INFO" 2>&1

echo ""
echo "=========================================="
echo "If the call succeeds, submit with --submit flag:"
echo ""
echo "./keep-client ethereum tbtc bridge reveal-deposit \\"
echo "  --ethereum.url $RPC_URL \\"
echo "  --ethereum.keyFile <your-keyfile> \\"
echo "  --submit \\"
echo "  \"\$FUNDING_TX\" \\"
echo "  \"\$REVEAL_INFO\""
echo ""
