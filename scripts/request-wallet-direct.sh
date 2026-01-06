#!/bin/bash
# Direct solution: Call WalletRegistry.requestNewWallet() directly
# This bypasses Bridge and works around the forwarding issue

set -e

cd "$(dirname "$0")/.."

WALLET_REGISTRY_ADDRESS="0xd49141e044801DEE237993deDf9684D59fafE2e6"
BRIDGE_ADDRESS="0xc0a2ee534F004a4ec2EFA541489acBD5ff4bBA99"

echo "=========================================="
echo "Direct Wallet Request (Workaround)"
echo "=========================================="
echo ""
echo "This script calls WalletRegistry.requestNewWallet() directly"
echo "using Geth console, which should work correctly."
echo ""
echo "WalletRegistry: $WALLET_REGISTRY_ADDRESS"
echo "Bridge (walletOwner): $BRIDGE_ADDRESS"
echo ""

# Check if we can use cast with --unlocked flag
if command -v cast >/dev/null 2>&1; then
  echo "Attempting with cast (using unlocked account)..."
  
  # Get first account
  FIRST_ACCOUNT=$(cast rpc eth_accounts --rpc-url http://localhost:8545 | jq -r '.[0]' 2>/dev/null || echo "")
  
  if [ -n "$FIRST_ACCOUNT" ]; then
    echo "Using account: $FIRST_ACCOUNT"
    echo ""
    echo "⚠️  Note: This will likely fail because cast can't impersonate Bridge"
    echo "   Use the Geth console method below instead."
    echo ""
  fi
fi

echo "=========================================="
echo "RECOMMENDED: Use Geth Console"
echo "=========================================="
echo ""
echo "The most reliable method is to use Geth console:"
echo ""
echo "  geth attach http://localhost:8545"
echo ""
echo "Then run these commands:"
echo ""
echo "  // Unlock an account"
echo "  personal.unlockAccount(eth.accounts[0], \"\", 0)"
echo ""
echo "  // Call Bridge.requestNewWallet()"
echo "  tx = eth.sendTransaction({"
echo "    from: eth.accounts[0],"
echo "    to: \"$BRIDGE_ADDRESS\","
echo "    data: \"0x72cc8c6d\","
echo "    gas: 500000"
echo "  })"
echo ""
echo "  console.log(\"Transaction hash:\", tx)"
echo ""
echo "After sending, check receipt:"
echo "  ./scripts/check-transaction-receipt.sh <tx-hash>"
echo ""
echo "=========================================="
echo "If Bridge forwarding still fails:"
echo "=========================================="
echo ""
echo "The issue is that Bridge -> WalletRegistry forwarding isn't"
echo "preserving msg.sender correctly. This is a known issue with"
echo "some contract interaction methods."
echo ""
echo "Possible solutions:"
echo "  1. Redeploy Bridge contract"
echo "  2. Update WalletRegistry to allow direct calls (development only)"
echo "  3. Use a different method to trigger DKG"
echo ""

