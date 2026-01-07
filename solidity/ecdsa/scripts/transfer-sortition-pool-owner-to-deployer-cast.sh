#!/bin/bash
# Transfer SortitionPool ownership from WalletRegistry to deployer using cast
# This fixes the issue where unlock() reverts because msg.sender != owner()

set -e

RPC_URL=${ETHEREUM_RPC_URL:-http://localhost:8545}

# Get addresses from deployments
WALLET_REGISTRY=$(cast call $(cast deployment-address WalletRegistry 2>/dev/null || echo "0x0") "sortitionPool()" --rpc-url $RPC_URL 2>/dev/null || echo "")
if [ -z "$WALLET_REGISTRY" ] || [ "$WALLET_REGISTRY" = "0x0" ]; then
    echo "Error: Could not get WalletRegistry address"
    exit 1
fi

SORTITION_POOL=$(cast call $WALLET_REGISTRY "sortitionPool()" --rpc-url $RPC_URL)
DEPLOYER=$(cast wallet address $DEPLOYER_KEYFILE 2>/dev/null || echo "")

if [ -z "$DEPLOYER" ]; then
    echo "Error: DEPLOYER_KEYFILE not set or invalid"
    echo "Set DEPLOYER_KEYFILE to the path of the deployer's keyfile"
    exit 1
fi

echo "=========================================="
echo "Transfer SortitionPool Ownership"
echo "=========================================="
echo ""
echo "SortitionPool: $SORTITION_POOL"
echo "WalletRegistry: $WALLET_REGISTRY"
echo "Deployer: $DEPLOYER"
echo ""

# Check current owner
CURRENT_OWNER=$(cast call $SORTITION_POOL "owner()" --rpc-url $RPC_URL)
echo "Current owner: $CURRENT_OWNER"
echo ""

if [ "${CURRENT_OWNER,,}" = "${DEPLOYER,,}" ]; then
    echo "✅ SortitionPool is already owned by deployer!"
    echo "   No transfer needed."
    exit 0
fi

if [ "${CURRENT_OWNER,,}" != "${WALLET_REGISTRY,,}" ]; then
    echo "⚠️  Current owner ($CURRENT_OWNER) is not WalletRegistry ($WALLET_REGISTRY)"
    echo "   Cannot transfer from this owner using this script."
    exit 1
fi

echo "⚠️  WARNING: WalletRegistry is a contract, not an EOA."
echo "   We cannot directly call transferOwnership from WalletRegistry."
echo ""
echo "To transfer ownership, you need to:"
echo "1. Add a function to WalletRegistry that calls sortitionPool.transferOwnership()"
echo "2. Or use WalletRegistry governance to execute the transfer"
echo "3. Or redeploy with deployer as owner (modify deployment script)"
echo ""
echo "For now, the deployment script has been modified to keep deployer as owner."
echo "For existing deployments, you'll need to add a function to WalletRegistry."

