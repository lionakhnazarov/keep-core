#!/bin/bash
# Setup script for redemption testing
# This explains the current state and what needs to be done

set -e

RPC_URL="${RPC_URL:-http://localhost:8545}"
BRIDGE="${BRIDGE_ADDRESS:-0x7C1Aeaa16b0e4C491105E061748A08cbD663d113}"
WALLET_REGISTRY="${WALLET_REGISTRY:-0xd49141e044801DEE237993deDf9684D59fafE2e6}"

echo "=========================================="
echo "Redemption Testing Setup"
echo "=========================================="
echo ""

# Check current state
echo "1. Checking Bridge deployment..."
BRIDGE_CODE=$(cast code $BRIDGE --rpc-url $RPC_URL 2>/dev/null || echo "")
if [ -n "$BRIDGE_CODE" ] && [ "$BRIDGE_CODE" != "0x" ]; then
    echo "   ✓ Bridge is deployed at $BRIDGE"
else
    echo "   ✗ Bridge not found"
    exit 1
fi

echo ""
echo "2. Checking walletOwner in WalletRegistry..."
WALLET_OWNER=$(cast call $WALLET_REGISTRY "walletOwner()(address)" --rpc-url $RPC_URL 2>/dev/null || echo "")
if [ "$WALLET_OWNER" = "$BRIDGE" ]; then
    echo "   ✓ walletOwner is set to Bridge"
else
    echo "   ✗ walletOwner is $WALLET_OWNER (expected $BRIDGE)"
    echo "   Run: ./scripts/update-wallet-owner.sh $BRIDGE"
fi

echo ""
echo "3. Checking DKG state..."
DKG_STATE=$(cast call $WALLET_REGISTRY "getWalletCreationState()(uint8)" --rpc-url $RPC_URL 2>/dev/null || echo "255")
case $DKG_STATE in
    0) echo "   ✓ DKG is IDLE - ready to request new wallet" ;;
    1) echo "   ⏳ DKG is AWAITING_SEED" ;;
    2) 
        echo "   ⏳ DKG is AWAITING_RESULT"
        TIMED_OUT=$(cast call $WALLET_REGISTRY "hasDkgTimedOut()(bool)" --rpc-url $RPC_URL 2>/dev/null || echo "false")
        if [ "$TIMED_OUT" = "true" ]; then
            echo "      → DKG has timed out - can reset"
        else
            echo "      → DKG still in progress"
        fi
        ;;
    3) echo "   ⏳ DKG is in CHALLENGE state" ;;
    *) echo "   ? Unknown DKG state: $DKG_STATE" ;;
esac

echo ""
echo "4. Checking existing wallets in Bridge..."
WALLET_FOUND=false
for HASH in "0x9850b965a0ef404ce03dd88691201cc537beaefd" "0x49be77e65eaa59efe636c5757fd3c31fc5efbb66" "0xfed577fbba8e72ec01810e12b09d974d7ef6b6bf"; do
    STATE=$(cast call $BRIDGE "wallets(bytes20)(bytes32,bytes32,uint64,uint32,uint32,uint32,uint8,bytes32)" "$HASH" --rpc-url $RPC_URL 2>/dev/null | sed -n '7p' || echo "0")
    if [ "$STATE" != "0" ]; then
        echo "   ✓ Wallet $HASH is registered (state=$STATE)"
        WALLET_FOUND=true
    fi
done

if [ "$WALLET_FOUND" = false ]; then
    echo "   ✗ No wallets registered in Bridge yet"
fi

echo ""
echo "=========================================="
echo "Current Situation"
echo "=========================================="
echo ""

if [ "$WALLET_FOUND" = false ]; then
    echo "Existing wallets were created with the old BridgeStub and are"
    echo "NOT registered in the new Bridge contract."
    echo ""
    echo "To test redemptions, you need to create a new wallet via DKG."
    echo "The new wallet will be automatically registered in the Bridge."
fi

echo ""
echo "=========================================="
echo "Steps to Enable Redemption Testing"
echo "=========================================="
echo ""
echo "1. If DKG is stuck, wait for timeout and reset:"
echo "   ./scripts/monitor-coordination-window.sh  # monitor blocks"
echo "   # When hasDkgTimedOut() returns true:"
echo "   cast send $WALLET_REGISTRY \"notifyDkgTimeout()\" --unlocked --from <ACCOUNT>"
echo ""
echo "2. Request a new wallet (after DKG is IDLE):"
echo "   cast send $BRIDGE \"requestNewWallet((bytes32,uint32,uint64))\" \"(0x0,0,0)\" --unlocked --from <ACCOUNT>"
echo ""
echo "3. Wait for DKG to complete (creates wallet registered in Bridge)"
echo ""
echo "4. Request redemption:"
echo "   ./scripts/request-redemption.sh --wallet <HASH> --amount 100000 --script 0x76a914...88ac"
echo ""
echo "=========================================="
