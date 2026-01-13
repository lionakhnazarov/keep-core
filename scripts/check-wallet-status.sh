#!/bin/bash
# Check if a wallet is live/registered in WalletRegistry

WALLET_ID="${1}"
WALLET_REGISTRY="${2:-0xd49141e044801DEE237993deDf9684D59fafE2e6}"
RPC_URL="${3:-http://localhost:8545}"

if [ -z "$WALLET_ID" ]; then
    echo "Usage: $0 <walletID> [walletRegistry] [rpcUrl]"
    echo ""
    echo "Example:"
    echo "  $0 0x1234...5678"
    echo "  $0 0x1234...5678 0xd49141e044801DEE237993deDf9684D59fafE2e6 http://localhost:8545"
    exit 1
fi

echo "Checking wallet status..."
echo "Wallet ID: $WALLET_ID"
echo "WalletRegistry: $WALLET_REGISTRY"
echo ""

# Check if wallet is registered
IS_REGISTERED=$(cast call "$WALLET_REGISTRY" "isWalletRegistered(bytes32)(bool)" "$WALLET_ID" --rpc-url "$RPC_URL" 2>/dev/null || echo "false")

if [ "$IS_REGISTERED" = "true" ]; then
    echo "✓ Wallet is REGISTERED and LIVE"
    echo ""
    echo "Getting wallet details..."
    
    # Get wallet info
    WALLET_INFO=$(cast call "$WALLET_REGISTRY" "getWallet(bytes32)(bytes32,bytes32,bytes32)" "$WALLET_ID" --rpc-url "$RPC_URL" 2>/dev/null)
    
    if [ -n "$WALLET_INFO" ]; then
        echo "$WALLET_INFO" | head -3 | while IFS= read -r line; do
            if [ -n "$line" ]; then
                echo "  $line"
            fi
        done
    fi
    
    # Get public key
    PUBLIC_KEY=$(cast call "$WALLET_REGISTRY" "getWalletPublicKey(bytes32)(bytes)" "$WALLET_ID" --rpc-url "$RPC_URL" 2>/dev/null)
    if [ -n "$PUBLIC_KEY" ] && [ "$PUBLIC_KEY" != "0x" ]; then
        echo ""
        echo "Public Key: $PUBLIC_KEY"
    fi
else
    echo "✗ Wallet is NOT registered (not live)"
    echo ""
    echo "Note: A wallet is 'live' if it's registered in WalletRegistry."
    echo "      When a wallet is closed, it's deleted from the registry."
fi
