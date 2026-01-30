#!/bin/bash
# DEV ONLY: Register an existing wallet in the Bridge contract
# This bypasses the normal flow where WalletRegistry calls the callback
#
# In production, wallets are registered automatically when created via DKG.
# This script is for development testing only.

set -e

RPC_URL="${RPC_URL:-http://localhost:8545}"
BRIDGE="${BRIDGE_ADDRESS:-0x7C1Aeaa16b0e4C491105E061748A08cbD663d113}"
WALLET_REGISTRY="${WALLET_REGISTRY:-0xd49141e044801DEE237993deDf9684D59fafE2e6}"

echo "=========================================="
echo "DEV: Register Wallet in Bridge"
echo "=========================================="
echo ""
echo "Bridge: $BRIDGE"
echo "WalletRegistry: $WALLET_REGISTRY"
echo ""

# Get wallet IDs that have public keys
echo "Finding wallets with public keys..."

# Get all WalletCreated events
WALLET_IDS=$(cast logs --from-block 0 --to-block latest \
    "WalletCreated(bytes32 walletID, bytes32 dkgResultHash)" \
    --address $WALLET_REGISTRY \
    --rpc-url $RPC_URL 2>/dev/null | grep -oE '0x[a-fA-F0-9]{64}' | sort -u)

REGISTERED=0
FAILED=0

for WALLET_ID in $WALLET_IDS; do
    # Get public key
    PUBKEY=$(cast call $WALLET_REGISTRY "getWalletPublicKey(bytes32)(bytes)" "$WALLET_ID" --rpc-url $RPC_URL 2>/dev/null || echo "")
    
    if [ -z "$PUBKEY" ] || [ "$PUBKEY" = "0x" ] || [ ${#PUBKEY} -lt 130 ]; then
        continue
    fi
    
    echo "Processing wallet: ${WALLET_ID:0:18}..."
    
    # Extract X and Y from pubkey (format: 0x + 64 hex chars X + 64 hex chars Y)
    PUBKEY_CLEAN=${PUBKEY:2}
    PUBKEY_X="0x${PUBKEY_CLEAN:0:64}"
    PUBKEY_Y="0x${PUBKEY_CLEAN:64:64}"
    
    # Check if already registered
    STATE=$(cast call $BRIDGE "wallets(bytes20)(bytes32,bytes32,uint64,uint32,uint32,uint32,uint8,bytes32)" \
        "0x0000000000000000000000000000000000000000" --rpc-url $RPC_URL 2>/dev/null | tail -2 | head -1 || echo "0")
    
    # Use hardhat's impersonation to call from WalletRegistry
    # This requires the node to support account impersonation
    
    echo "  Impersonating WalletRegistry to call Bridge..."
    
    # First, unlock the WalletRegistry account for impersonation
    cast rpc anvil_impersonateAccount "$WALLET_REGISTRY" --rpc-url $RPC_URL 2>/dev/null || \
    cast rpc hardhat_impersonateAccount "$WALLET_REGISTRY" --rpc-url $RPC_URL 2>/dev/null || true
    
    # Fund the impersonated account
    FUNDER=$(cast rpc eth_accounts --rpc-url $RPC_URL 2>/dev/null | jq -r '.[0]')
    cast send $WALLET_REGISTRY --value 0.1ether --from $FUNDER --unlocked --rpc-url $RPC_URL 2>/dev/null || true
    
    # Call the callback
    TX_RESULT=$(cast send $BRIDGE \
        "__ecdsaWalletCreatedCallback(bytes32,bytes32,bytes32)" \
        "$WALLET_ID" \
        "$PUBKEY_X" \
        "$PUBKEY_Y" \
        --rpc-url $RPC_URL \
        --unlocked \
        --from $WALLET_REGISTRY \
        --gas-limit 500000 \
        2>&1) || true
    
    # Stop impersonation
    cast rpc anvil_stopImpersonatingAccount "$WALLET_REGISTRY" --rpc-url $RPC_URL 2>/dev/null || \
    cast rpc hardhat_stopImpersonatingAccount "$WALLET_REGISTRY" --rpc-url $RPC_URL 2>/dev/null || true
    
    if echo "$TX_RESULT" | grep -qi "transactionHash"; then
        echo "  ✓ Registered successfully"
        ((REGISTERED++))
    else
        echo "  ✗ Failed: ${TX_RESULT:0:80}..."
        ((FAILED++))
    fi
    
    echo ""
done

echo "=========================================="
echo "Summary"
echo "=========================================="
echo "Registered: $REGISTERED"
echo "Failed: $FAILED"
echo ""

if [ $REGISTERED -eq 0 ] && [ $FAILED -gt 0 ]; then
    echo "Note: Account impersonation may not be supported on your node."
    echo ""
    echo "Alternative: Deploy a helper contract to register wallets,"
    echo "or use governance to update the Bridge."
fi
