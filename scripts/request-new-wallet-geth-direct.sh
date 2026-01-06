#!/bin/bash
# Script to request a new wallet using geth console directly
# This bypasses Hardhat and calls WalletRegistry directly as Bridge

set -e

cd "$(dirname "$0")/.."

# Get Bridge address
BRIDGE_ADDRESS=""
if [ -f "solidity/tbtc-stub/deployments/development/Bridge.json" ]; then
  BRIDGE_ADDRESS=$(cat solidity/tbtc-stub/deployments/development/Bridge.json | grep -o '"address": "[^"]*"' | cut -d'"' -f4)
fi

if [ -z "$BRIDGE_ADDRESS" ]; then
  echo "Error: Could not find Bridge address"
  echo "Please deploy Bridge first"
  exit 1
fi

# Get WalletRegistry address
WALLET_REGISTRY_ADDRESS=""
if [ -f "solidity/ecdsa/deployments/development/WalletRegistry.json" ]; then
  WALLET_REGISTRY_ADDRESS=$(cat solidity/ecdsa/deployments/development/WalletRegistry.json | grep -o '"address": "[^"]*"' | cut -d'"' -f4)
fi

if [ -z "$WALLET_REGISTRY_ADDRESS" ]; then
  echo "Error: Could not find WalletRegistry address"
  exit 1
fi

echo "=========================================="
echo "Request New Wallet via Geth Console"
echo "=========================================="
echo ""
echo "Bridge address: $BRIDGE_ADDRESS"
echo "WalletRegistry address: $WALLET_REGISTRY_ADDRESS"
echo ""

# Function selector for requestNewWallet()
FUNCTION_SELECTOR="0x72cc8c6d"

echo "Method 1: Call Bridge.requestNewWallet()"
echo "----------------------------------------"
echo "This should forward to WalletRegistry:"
echo ""
echo "geth attach http://localhost:8545"
echo "> personal.unlockAccount(eth.accounts[0], \"\", 0)"
echo "> eth.sendTransaction({from: eth.accounts[0], to: \"$BRIDGE_ADDRESS\", data: \"$FUNCTION_SELECTOR\", gas: 500000})"
echo ""

echo "Method 2: Impersonate Bridge and call WalletRegistry directly"
echo "-------------------------------------------------------------"
echo "If your Geth supports eth_impersonateAccount:"
echo ""
echo "geth attach http://localhost:8545"
echo "> eth_impersonateAccount(\"$BRIDGE_ADDRESS\")"
echo "> personal.unlockAccount(\"$BRIDGE_ADDRESS\", \"\", 0)"
echo "> eth.sendTransaction({from: \"$BRIDGE_ADDRESS\", to: \"$WALLET_REGISTRY_ADDRESS\", data: \"$FUNCTION_SELECTOR\", gas: 500000})"
echo ""

echo "Method 3: Use cast with unlocked account"
echo "----------------------------------------"
echo "cast send $BRIDGE_ADDRESS \"requestNewWallet()\" \\"
echo "  --rpc-url http://localhost:8545 \\"
echo "  --unlocked \\"
echo "  --from \$(cast rpc eth_accounts --rpc-url http://localhost:8545 | jq -r '.[0]')"
echo ""

# Try to execute Method 3 automatically if cast is available
if command -v cast >/dev/null 2>&1; then
  echo "Attempting Method 3 automatically..."
  echo ""
  
  # Get first account
  FIRST_ACCOUNT=$(cast rpc eth_accounts --rpc-url http://localhost:8545 2>/dev/null | jq -r '.[0]' 2>/dev/null || echo "")
  
  if [ -n "$FIRST_ACCOUNT" ]; then
    echo "Using account: $FIRST_ACCOUNT"
    echo "Unlocking account in Geth..."
    
    # Try to unlock via RPC
    curl -s -X POST http://localhost:8545 \
      -H "Content-Type: application/json" \
      -d "{\"jsonrpc\":\"2.0\",\"method\":\"personal_unlockAccount\",\"params\":[\"$FIRST_ACCOUNT\",\"\",0],\"id\":1}" > /dev/null
    
    echo "Sending transaction..."
    cast send "$BRIDGE_ADDRESS" "requestNewWallet()" \
      --rpc-url http://localhost:8545 \
      --unlocked \
      --from "$FIRST_ACCOUNT" || {
        echo ""
        echo "⚠️  Automatic execution failed. Please use one of the manual methods above."
        exit 1
      }
    
    echo ""
    echo "✓ Transaction sent successfully!"
    echo "Check transaction receipt with:"
    echo "  ./scripts/check-transaction-receipt.sh <tx-hash>"
  else
    echo "Could not get account from Geth. Please use manual methods above."
  fi
else
  echo "cast not found. Please install foundry or use manual methods above."
fi

