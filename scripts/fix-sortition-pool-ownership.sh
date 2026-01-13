#!/bin/bash
# Fix SortitionPool ownership - transfer to WalletRegistry
# This is required for WalletRegistry to call lock() on the SortitionPool

set -e

cd "$(dirname "$0")/.."

SORTITION_POOL_ADDRESS="0x88b2480f0014ED6789690C1c4F35Fc230ef83458"
WALLET_REGISTRY_ADDRESS="0xd49141e044801DEE237993deDf9684D59fafE2e6"
CURRENT_OWNER="0x2e666F38Cf0A5ed375AE5ae2c40baed553410038"

echo "=========================================="
echo "Fix SortitionPool Ownership"
echo "=========================================="
echo ""
echo "SortitionPool: $SORTITION_POOL_ADDRESS"
echo "Current Owner: $CURRENT_OWNER"
echo "New Owner (WalletRegistry): $WALLET_REGISTRY_ADDRESS"
echo ""

# Check current owner
echo "Checking current owner..."
CURRENT_OWNER_CHECK=$(cast call "$SORTITION_POOL_ADDRESS" "owner()" --rpc-url http://localhost:8545 2>/dev/null | cast --parse-bytes32-address || cast call "$SORTITION_POOL_ADDRESS" "owner()" --rpc-url http://localhost:8545)
echo "Current owner: $CURRENT_OWNER_CHECK"
echo ""

if [ "$CURRENT_OWNER_CHECK" = "$WALLET_REGISTRY_ADDRESS" ]; then
  echo "✅ SortitionPool is already owned by WalletRegistry!"
  exit 0
fi

# Get the first account for sending the transaction
FIRST_ACCOUNT=$(cast rpc eth_accounts --rpc-url http://localhost:8545 | jq -r '.[0]' 2>/dev/null || echo "")

if [ -z "$FIRST_ACCOUNT" ]; then
  echo "Error: Could not get accounts from Geth"
  exit 1
fi

echo "Using account: $FIRST_ACCOUNT"
echo ""

# Check if we need to impersonate the current owner
if [ "$CURRENT_OWNER_CHECK" != "$FIRST_ACCOUNT" ]; then
  echo "⚠️  Current owner ($CURRENT_OWNER_CHECK) is different from your account ($FIRST_ACCOUNT)"
  echo ""
  echo "You need to transfer ownership. Options:"
  echo ""
  echo "Option 1: Use Geth console to impersonate owner (if supported)"
  echo "  geth attach http://localhost:8545"
  echo "  // Impersonate owner"
  echo "  personal.unlockAccount('$CURRENT_OWNER_CHECK', '', 0)"
  echo "  // Transfer ownership"
  echo "  eth.sendTransaction({"
  echo "    from: '$CURRENT_OWNER_CHECK',"
  echo "    to: '$SORTITION_POOL_ADDRESS',"
  echo "    data: '0xf2fde38b' + '$WALLET_REGISTRY_ADDRESS'.slice(2).padStart(64, '0'),"
  echo "    gas: 100000"
  echo "  })"
  echo ""
  echo "Option 2: Use cast with owner's private key"
  echo "  cast send $SORTITION_POOL_ADDRESS 'transferOwnership(address)' '$WALLET_REGISTRY_ADDRESS' \\"
  echo "    --rpc-url http://localhost:8545 \\"
  echo "    --private-key <owner-private-key>"
  echo ""
  exit 1
fi

echo "Transferring ownership to WalletRegistry..."
echo ""

# Transfer ownership
TX_HASH=$(cast send "$SORTITION_POOL_ADDRESS" "transferOwnership(address)" "$WALLET_REGISTRY_ADDRESS" \
  --rpc-url http://localhost:8545 \
  --unlocked \
  --from "$FIRST_ACCOUNT" \
  2>&1 | grep -oP '0x[a-fA-F0-9]{64}' | head -1 || echo "")

if [ -n "$TX_HASH" ]; then
  echo "✅ Ownership transfer transaction sent!"
  echo "Transaction hash: $TX_HASH"
  echo ""
  echo "Waiting for confirmation..."
  sleep 3
  
  # Verify new owner
  NEW_OWNER=$(cast call "$SORTITION_POOL_ADDRESS" "owner()" --rpc-url http://localhost:8545 2>/dev/null | cast --parse-bytes32-address || cast call "$SORTITION_POOL_ADDRESS" "owner()" --rpc-url http://localhost:8545)
  
  if [ "$NEW_OWNER" = "$WALLET_REGISTRY_ADDRESS" ]; then
    echo "✅ Ownership successfully transferred to WalletRegistry!"
  else
    echo "⚠️  Ownership transfer may still be pending. New owner: $NEW_OWNER"
  fi
else
  echo "❌ Failed to send transaction"
  exit 1
fi


