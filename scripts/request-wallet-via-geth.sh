#!/bin/bash
# Simple script to request new wallet via Geth console
# This is the most reliable method

set -e

cd "$(dirname "$0")/.."

BRIDGE_ADDRESS="0xc0a2ee534F004a4ec2EFA541489acBD5ff4bBA99"
WALLET_REGISTRY_ADDRESS="0xd49141e044801DEE237993deDf9684D59fafE2e6"

echo "=========================================="
echo "Request New Wallet via Geth Console"
echo "=========================================="
echo ""
echo "Bridge: $BRIDGE_ADDRESS"
echo "WalletRegistry: $WALLET_REGISTRY_ADDRESS"
echo ""
echo "Opening Geth console..."
echo ""
echo "Run these commands in order:"
echo ""
echo "1. Unlock an account:"
echo "   personal.unlockAccount(eth.accounts[0], \"\", 0)"
echo ""
echo "2. Send transaction to Bridge:"
echo "   eth.sendTransaction({"
echo "     from: eth.accounts[0],"
echo "     to: \"$BRIDGE_ADDRESS\","
echo "     data: \"0x72cc8c6d\","
echo "     gas: 500000"
echo "   })"
echo ""
echo "This will call Bridge.requestNewWallet(), which forwards to"
echo "WalletRegistry.requestNewWallet(). WalletRegistry will see Bridge"
echo "as msg.sender (the walletOwner), so it will succeed."
echo ""
echo "After sending, copy the transaction hash and check it with:"
echo "   ./scripts/check-transaction-receipt.sh <tx-hash>"
echo ""

# Try to open geth console automatically
if command -v geth >/dev/null 2>&1; then
  echo "Opening Geth console now..."
  echo ""
  geth attach http://localhost:8545
else
  echo "Geth not found in PATH. Please run 'geth attach http://localhost:8545' manually."
fi

