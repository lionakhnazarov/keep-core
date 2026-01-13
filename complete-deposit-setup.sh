#!/bin/bash
# Complete setup for deposit testing

BRIDGE="0xc7BC782Da1AAb7ee5985aC94C575f374FA4C75e5"
WR="0xd49141e044801DEE237993deDf9684D59fafE2e6"
WR_GOV="0x1bef6019c28a61130c5c04f6b906a16c85397cea"
RPC_URL="http://localhost:8545"
ACCOUNT=$(cast rpc eth_accounts --rpc-url $RPC_URL 2>/dev/null | jq -r '.[0]')

echo "=========================================="
echo "Complete Deposit Testing Setup"
echo "=========================================="
echo ""

# Step 1: Fund governance
echo "Step 1: Funding governance account..."
cast send --value $(cast --to-wei 1 ether) --to $WR_GOV --rpc-url $RPC_URL --unlocked --from $ACCOUNT 2>&1 | grep transactionHash || echo "Funding..."

# Wait a moment
sleep 2

# Step 2: Begin wallet owner update
echo ""
echo "Step 2: Beginning wallet owner update..."
cast send $WR_GOV "beginWalletOwnerUpdate(address)" $BRIDGE \
  --rpc-url $RPC_URL --unlocked --from $WR_GOV 2>&1 | grep -E "transactionHash|Error" | head -2

# Step 3: Check delay and finalize if 0
DELAY=$(cast call $WR_GOV "governanceDelay()" --rpc-url $RPC_URL 2>/dev/null | cast --to-dec)
echo ""
echo "Governance delay: $DELAY seconds"

if [ "$DELAY" = "0" ]; then
  echo "Finalizing immediately..."
  cast send $WR_GOV "finalizeWalletOwnerUpdate()" \
    --rpc-url $RPC_URL --unlocked --from $WR_GOV 2>&1 | grep -E "transactionHash|Error" | head -2
  
  # Verify
  sleep 2
  NEW_OWNER=$(cast call $WR "walletOwner()" --rpc-url $RPC_URL 2>/dev/null | sed 's/0x000000000000000000000000/0x/')
  if [ "$NEW_OWNER" = "$BRIDGE" ]; then
    echo ""
    echo "✅ Bridge is now walletOwner!"
    echo ""
    echo "Step 3: Request new wallet..."
    echo "   Run: ./scripts/request-new-wallet.sh"
    echo ""
    echo "Step 4: Wait for DKG and check status:"
    echo "   ./check-wallet-bridge-status.sh"
  fi
else
  echo ""
  echo "⏳ Wait $DELAY seconds, then run:"
  echo "cast send $WR_GOV \"finalizeWalletOwnerUpdate()\" --rpc-url $RPC_URL --unlocked --from $WR_GOV"
fi
echo ""
