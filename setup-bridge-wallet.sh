#!/bin/bash
# Setup Bridge as walletOwner and create new wallet

BRIDGE="0xc7BC782Da1AAb7ee5985aC94C575f374FA4C75e5"
WR="0xd49141e044801DEE237993deDf9684D59fafE2e6"
RPC_URL="http://localhost:8545"
ACCOUNT=$(cast rpc eth_accounts --rpc-url $RPC_URL 2>/dev/null | jq -r '.[0]')

echo "=========================================="
echo "Setting up Bridge for Deposits"
echo "=========================================="
echo ""

# Check current walletOwner
CURRENT_OWNER=$(cast call $WR "walletOwner()" --rpc-url $RPC_URL 2>/dev/null)
echo "Current walletOwner: $CURRENT_OWNER"
echo "Target Bridge: $BRIDGE"
echo ""

if [ "$CURRENT_OWNER" != "$BRIDGE" ]; then
  echo "Step 1: Setting Bridge as walletOwner..."
  echo "   (This requires governance permissions)"
  echo ""
  
  # Try to get governance address
  GOVERNANCE=$(cast call $WR "governance()" --rpc-url $RPC_URL 2>/dev/null || echo "")
  if [ -n "$GOVERNANCE" ] && [ "$GOVERNANCE" != "0x0000000000000000000000000000000000000000" ]; then
    echo "   Governance address: $GOVERNANCE"
    echo "   Run as governance:"
    echo "   cast send $WR \"updateWalletOwner(address)\" $BRIDGE \\"
    echo "     --rpc-url $RPC_URL --unlocked --from $GOVERNANCE"
  else
    echo "   ⚠️  No governance found. In development, you may need to:"
    echo "   1. Check if WalletRegistry has a setter function"
    echo "   2. Or deploy with governance set to your account"
    echo ""
    echo "   Trying with current account..."
    cast send $WR "updateWalletOwner(address)" $BRIDGE \
      --rpc-url $RPC_URL --unlocked --from $ACCOUNT 2>&1 | head -5 || echo "   ❌ Failed - need governance"
  fi
  echo ""
fi

echo "Step 2: Request new wallet (will be registered in Bridge automatically)..."
echo "   Run: ./scripts/request-new-wallet.sh"
echo ""
echo "Step 3: Wait for DKG to complete"
echo ""
echo "Step 4: Check wallet status:"
echo "   ./check-wallet-bridge-status.sh"
echo ""
