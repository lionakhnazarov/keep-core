#!/bin/bash
# Update WalletRegistry walletOwner via governance

BRIDGE_ADDRESS="${1}"
WALLET_REGISTRY_GOV="${2:-$(jq -r '.address' solidity/ecdsa/deployments/development/WalletRegistryGovernance.json 2>/dev/null || echo '')}"
RPC_URL="${3:-http://localhost:8545}"

if [ -z "$BRIDGE_ADDRESS" ]; then
    echo "Usage: $0 <bridgeAddress> [walletRegistryGovernance] [rpcUrl]"
    echo ""
    echo "Example:"
    echo "  $0 0xc0a2ee534F004a4ec2EFA541489acBD5ff4bBA99"
    exit 1
fi

if [ -z "$WALLET_REGISTRY_GOV" ] || [ "$WALLET_REGISTRY_GOV" = "null" ]; then
    echo "✗ WalletRegistryGovernance not found"
    exit 1
fi

echo "Updating walletOwner to Bridge address..."
echo "Bridge: $BRIDGE_ADDRESS"
echo "Governance: $WALLET_REGISTRY_GOV"
echo ""

# Get governance owner
OWNER=$(cast call "$WALLET_REGISTRY_GOV" "owner()(address)" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
if [ -z "$OWNER" ] || [ "$OWNER" = "0x0000000000000000000000000000000000000000" ]; then
    echo "✗ Could not get governance owner"
    exit 1
fi

echo "Governance owner: $OWNER"
echo ""

# Begin update
echo "1. Initiating walletOwner update..."
BEGIN_TX=$(cast send "$WALLET_REGISTRY_GOV" \
    "beginWalletOwnerUpdate(address)" "$BRIDGE_ADDRESS" \
    --rpc-url "$RPC_URL" \
    --unlocked \
    --from "$OWNER" \
    --gas-limit 200000 2>&1 | grep -E "transactionHash" | grep -oE '0x[a-fA-F0-9]{64}' || echo "")

if [ -z "$BEGIN_TX" ]; then
    echo "✗ Failed to initiate update"
    exit 1
fi

echo "✓ Update initiated (tx: ${BEGIN_TX:0:10}...)"
echo ""

# Wait for governance delay
echo "2. Waiting for governance delay (65 seconds)..."
sleep 65

# Finalize update
echo "3. Finalizing walletOwner update..."
FINALIZE_TX=$(cast send "$WALLET_REGISTRY_GOV" \
    "finalizeWalletOwnerUpdate()" \
    --rpc-url "$RPC_URL" \
    --unlocked \
    --from "$OWNER" \
    --gas-limit 200000 2>&1 | grep -E "transactionHash|status" | head -3)

if echo "$FINALIZE_TX" | grep -q "status.*1"; then
    echo "✓ Update finalized successfully"
    sleep 2
    
    # Verify
    WALLET_REGISTRY=$(jq -r '.address' solidity/ecdsa/deployments/development/WalletRegistry.json 2>/dev/null || echo "")
    if [ -n "$WALLET_REGISTRY" ] && [ "$WALLET_REGISTRY" != "null" ]; then
        NEW_OWNER=$(cast call "$WALLET_REGISTRY" "walletOwner()(address)" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
        if [ "$NEW_OWNER" = "$BRIDGE_ADDRESS" ]; then
            echo ""
            echo "✓✓✓ SUCCESS! walletOwner updated to Bridge address"
            echo "   New walletOwner: $NEW_OWNER"
        else
            echo ""
            echo "✗ Verification failed (current: $NEW_OWNER, expected: $BRIDGE_ADDRESS)"
        fi
    fi
else
    echo "✗ Failed to finalize update"
    exit 1
fi
