#!/bin/bash
# Complete deposit testing script

BRIDGE="0xc7BC782Da1AAb7ee5985aC94C575f374FA4C75e5"
RPC_URL="http://localhost:8545"
WR="0xd49141e044801DEE237993deDf9684D59fafE2e6"  # WalletRegistry from earlier

# Get first account
ACCOUNT=$(cast rpc eth_accounts --rpc-url "$RPC_URL" 2>/dev/null | jq -r '.[0]' 2>/dev/null || echo "")

echo "=========================================="
echo "Deposit Testing Guide"
echo "=========================================="
echo "Bridge: $BRIDGE"
echo "WalletRegistry: $WR"
echo "Account: $ACCOUNT"
echo ""

# Check wallet status
echo "Step 1: Checking wallet status..."
WALLET_ID=$(cast logs --from-block 0 --to-block latest \
  --address "$WR" \
  "WalletCreated(bytes32,bytes32)" \
  --rpc-url "$RPC_URL" 2>/dev/null | jq -r '.[-1].topics[1]' 2>/dev/null || echo "")

if [ -n "$WALLET_ID" ] && [ "$WALLET_ID" != "null" ]; then
  echo "✅ Found wallet: $WALLET_ID"
  echo ""
  echo "Step 2: Check wallet state (should be Live/2 for deposits):"
  echo "cast call $WR \"getWallet(bytes32)\" $WALLET_ID --rpc-url $RPC_URL"
else
  echo "⚠️  No wallets found. Create one first:"
  echo "./scripts/request-new-wallet.sh"
  exit 1
fi

echo ""
echo "Step 3: Once wallet is Live, reveal deposit with:"
echo ""
echo "cast send $BRIDGE \\"
echo "  \"revealDeposit((bytes4,bytes,bytes,bytes4),(uint32,bytes8,bytes20,bytes20,bytes4,address))\" \\"
echo "  \"(\$(cat deposit-data/funding-tx-info.json | jq -r '.version'),\$(cat deposit-data/funding-tx-info.json | jq -r '.inputVector'),\$(cat deposit-data/funding-tx-info.json | jq -r '.outputVector'),\$(cat deposit-data/funding-tx-info.json | jq -r '.locktime'))\" \\"
echo "  \"(\$(cat deposit-data/deposit-reveal-info.json | jq -r '.fundingOutputIndex'),\$(cat deposit-data/deposit-reveal-info.json | jq -r '.blindingFactor'),\$(cat deposit-data/deposit-reveal-info.json | jq -r '.walletPubKeyHash'),\$(cat deposit-data/deposit-reveal-info.json | jq -r '.refundPubKeyHash'),\$(cat deposit-data/deposit-reveal-info.json | jq -r '.refundLocktime'),\$(cat deposit-data/deposit-reveal-info.json | jq -r '.vault'))\" \\"
echo "  --rpc-url $RPC_URL \\"
echo "  --from $ACCOUNT \\"
echo "  --unlocked"
echo ""
