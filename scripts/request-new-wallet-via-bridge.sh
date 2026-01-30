#!/bin/bash
# Request a new wallet via the Bridge contract
# This is the proper way to create wallets that will be registered in Bridge

set -e

RPC_URL="${RPC_URL:-http://localhost:8545}"
BRIDGE="${BRIDGE_ADDRESS:-0x7C1Aeaa16b0e4C491105E061748A08cbD663d113}"
WALLET_REGISTRY="${WALLET_REGISTRY:-0xd49141e044801DEE237993deDf9684D59fafE2e6}"

echo "=========================================="
echo "Request New Wallet via Bridge"
echo "=========================================="
echo ""
echo "Bridge: $BRIDGE"
echo "WalletRegistry: $WALLET_REGISTRY"
echo ""

# Check DKG state
DKG_STATE=$(cast call $WALLET_REGISTRY "getWalletCreationState()(uint8)" --rpc-url $RPC_URL 2>/dev/null || echo "255")

if [ "$DKG_STATE" != "0" ]; then
    echo "❌ DKG is not IDLE (state=$DKG_STATE)"
    echo ""
    echo "DKG states: 0=IDLE, 1=AWAITING_SEED, 2=AWAITING_RESULT, 3=CHALLENGE"
    echo ""
    
    if [ "$DKG_STATE" = "2" ]; then
        TIMED_OUT=$(cast call $WALLET_REGISTRY "hasDkgTimedOut()(bool)" --rpc-url $RPC_URL 2>/dev/null || echo "false")
        if [ "$TIMED_OUT" = "true" ]; then
            echo "DKG has timed out. Resetting..."
            DEPLOYER=$(cast rpc eth_accounts --rpc-url $RPC_URL 2>/dev/null | jq -r '.[0]')
            cast send $WALLET_REGISTRY "notifyDkgTimeout()" --unlocked --from $DEPLOYER --rpc-url $RPC_URL
            sleep 2
        else
            echo "DKG is still in progress. Please wait."
            exit 1
        fi
    else
        exit 1
    fi
fi

echo "✓ DKG is IDLE - ready to request new wallet"
echo ""

# Get account to use
DEPLOYER=$(cast rpc eth_accounts --rpc-url $RPC_URL 2>/dev/null | jq -r '.[0]')
echo "Using account: $DEPLOYER"
echo ""

# Check if there's an active wallet with main UTXO
# For simplicity, use empty main UTXO
EMPTY_UTXO="(0x0000000000000000000000000000000000000000000000000000000000000000,0,0)"

echo "Requesting new wallet via Bridge..."
echo ""

# Call Bridge.requestNewWallet(BitcoinTx.UTXO calldata activeWalletMainUtxo)
TX_RESULT=$(cast send $BRIDGE \
    "requestNewWallet((bytes32,uint32,uint64))" \
    "$EMPTY_UTXO" \
    --rpc-url $RPC_URL \
    --unlocked \
    --from $DEPLOYER \
    2>&1)

if echo "$TX_RESULT" | grep -qi "transactionHash"; then
    TX_HASH=$(echo "$TX_RESULT" | grep "transactionHash" | grep -oE '0x[a-fA-F0-9]{64}')
    echo "✓ New wallet requested successfully!"
    echo "Transaction: $TX_HASH"
    echo ""
    
    # Check new DKG state
    sleep 2
    NEW_STATE=$(cast call $WALLET_REGISTRY "getWalletCreationState()(uint8)" --rpc-url $RPC_URL 2>/dev/null || echo "255")
    echo "DKG state is now: $NEW_STATE"
    case $NEW_STATE in
        1) echo "  → AWAITING_SEED (waiting for random beacon)" ;;
        2) echo "  → AWAITING_RESULT (DKG in progress)" ;;
        *) echo "  → State: $NEW_STATE" ;;
    esac
    
    echo ""
    echo "=========================================="
    echo "Next Steps"
    echo "=========================================="
    echo ""
    echo "1. Wait for DKG to complete (keep-clients will process)"
    echo "2. Monitor with: ./scripts/check-dkg-simple.sh"
    echo "3. Once complete, the new wallet will be registered in Bridge"
    echo "4. Then you can request redemptions"
else
    echo "❌ Failed to request new wallet"
    echo ""
    echo "$TX_RESULT"
    
    if echo "$TX_RESULT" | grep -qi "revert"; then
        echo ""
        echo "Possible causes:"
        echo "  - DKG not idle"
        echo "  - Active wallet balance conditions not met"
        echo "  - Caller not authorized"
    fi
    exit 1
fi
