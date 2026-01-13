#!/bin/bash
# Request new wallet by impersonating Bridge account
# This bypasses the cast gas estimation issue

set -e

cd "$(dirname "$0")/.."

BRIDGE_ADDRESS="0xc0a2ee534F004a4ec2EFA541489acBD5ff4bBA99"
WALLET_REGISTRY_ADDRESS="0xd49141e044801DEE237993deDf9684D59fafE2e6"

echo "=========================================="
echo "Request New Wallet (Impersonate Bridge)"
echo "=========================================="
echo ""
echo "Bridge: $BRIDGE_ADDRESS"
echo "WalletRegistry: $WALLET_REGISTRY_ADDRESS"
echo ""

# Check if cast is available
if ! command -v cast >/dev/null 2>&1; then
  echo "Error: cast is not installed. Please install foundry."
  exit 1
fi

# Get the first account for sending the transaction
FIRST_ACCOUNT=$(cast rpc eth_accounts --rpc-url http://localhost:8545 | jq -r '.[0]' 2>/dev/null || echo "")

if [ -z "$FIRST_ACCOUNT" ]; then
  echo "Error: Could not get accounts from Geth"
  exit 1
fi

echo "Using account: $FIRST_ACCOUNT"
echo ""

# Impersonate Bridge account
echo "Step 1: Impersonating Bridge account..."
cast rpc anvil_impersonateAccount "$BRIDGE_ADDRESS" --rpc-url http://localhost:8545 2>/dev/null || \
cast rpc evm_setAccountNonce "$BRIDGE_ADDRESS" 0 --rpc-url http://localhost:8545 2>/dev/null || \
echo "Note: Account impersonation may not be supported. Trying alternative method..."

echo "Step 2: Sending transaction from Bridge to WalletRegistry..."
echo ""

# Method 1: Try using cast with impersonation (if supported)
if cast rpc anvil_impersonateAccount "$BRIDGE_ADDRESS" --rpc-url http://localhost:8545 2>/dev/null; then
  echo "Using anvil_impersonateAccount..."
  TX_HASH=$(cast send "$WALLET_REGISTRY_ADDRESS" "requestNewWallet()" \
    --rpc-url http://localhost:8545 \
    --from "$BRIDGE_ADDRESS" \
    2>&1 | grep -oP '0x[a-fA-F0-9]{64}' | head -1 || echo "")
  
  if [ -n "$TX_HASH" ]; then
    echo "✅ Transaction sent successfully!"
    echo "Transaction hash: $TX_HASH"
    echo ""
    echo "Check status with:"
    echo "  cast receipt $TX_HASH --rpc-url http://localhost:8545"
    exit 0
  fi
fi

# Method 2: Use Geth console with low-level call
echo "Method 1 failed. Using Geth console method..."
echo ""
echo "Run these commands in Geth console (geth attach http://localhost:8545):"
echo ""
echo "// Unlock your account"
echo "personal.unlockAccount('$FIRST_ACCOUNT', '', 0)"
echo ""
echo "// Send transaction to Bridge.requestNewWallet()"
echo "// Function selector: 0x72cc8c6d"
echo "eth.sendTransaction({"
echo "  from: '$FIRST_ACCOUNT',"
echo "  to: '$BRIDGE_ADDRESS',"
echo "  data: '0x72cc8c6d',"
echo "  gas: 500000"
echo "})"
echo ""
echo "Or, if you want to call WalletRegistry directly (will fail unless Bridge is walletOwner):"
echo "eth.sendTransaction({"
echo "  from: '$FIRST_ACCOUNT',"
echo "  to: '$WALLET_REGISTRY_ADDRESS',"
echo "  data: '0x72cc8c6d',"
echo "  gas: 500000"
echo "})"
echo ""
echo "=========================================="
echo "Alternative: Use cast with --value 0"
echo "=========================================="
echo ""
echo "Try this command:"
echo "cast send $BRIDGE_ADDRESS 'requestNewWallet()' \\"
echo "  --rpc-url http://localhost:8545 \\"
echo "  --private-key <your-private-key> \\"
echo "  --gas-limit 500000"
echo ""


