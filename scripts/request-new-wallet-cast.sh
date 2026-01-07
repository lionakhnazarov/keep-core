#!/bin/bash
# Request new wallet using cast (bypasses Hardhat impersonation issues)
# This script calls Bridge.requestNewWallet() using cast, which properly
# forwards the call to WalletRegistry with Bridge as msg.sender

set -e

RPC_URL=${ETHEREUM_RPC_URL:-http://localhost:8545}
KEEP_ETHEREUM_PASSWORD=${KEEP_ETHEREUM_PASSWORD:-password}

echo "=========================================="
echo "Request New Wallet (Using cast)"
echo "=========================================="
echo ""

# Get Bridge address
BRIDGE=$(jq -r '.address' solidity/tbtc-stub/deployments/development/Bridge.json 2>/dev/null || echo "")
if [ -z "$BRIDGE" ] || [ "$BRIDGE" = "null" ]; then
    echo "Error: Bridge deployment not found"
    exit 1
fi

echo "Bridge address: $BRIDGE"
echo ""

# Get first account from Geth
ACCOUNT=$(cast rpc eth_accounts --rpc-url "$RPC_URL" 2>/dev/null | jq -r '.[0]' || echo "")
if [ -z "$ACCOUNT" ] || [ "$ACCOUNT" = "null" ]; then
    echo "Error: No accounts found in Geth"
    exit 1
fi

echo "Using account: $ACCOUNT"
echo ""

# Unlock account in Geth
echo "Unlocking account in Geth..."
cast rpc personal_unlockAccount --rpc-url "$RPC_URL" "$ACCOUNT" "$KEEP_ETHEREUM_PASSWORD" 0 >/dev/null 2>&1 || {
    echo "Warning: Could not unlock account (may already be unlocked)"
}

# Check DKG state first
WALLET_REGISTRY=$(cast call "$BRIDGE" "ecdsaWalletRegistry()" --rpc-url "$RPC_URL")
DKG_STATE=$(cast call "$WALLET_REGISTRY" "getWalletCreationState()(uint8)" --rpc-url "$RPC_URL" || echo "255")

if [ "$DKG_STATE" = "255" ]; then
    echo "Warning: Could not check DKG state"
elif [ "$DKG_STATE" != "0" ]; then
    STATE_NAMES=("IDLE" "AWAITING_SEED" "AWAITING_RESULT" "CHALLENGE")
    STATE_NAME=${STATE_NAMES[$DKG_STATE]:-UNKNOWN}
    echo "⚠️  DKG is not in IDLE state (current: $STATE_NAME)"
    echo "   requestNewWallet() may revert"
    echo ""
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    echo "✓ DKG is in IDLE state - ready to request new wallet"
fi

echo ""
echo "Calling Bridge.requestNewWallet()..."
echo ""

# Call Bridge.requestNewWallet() using cast
TX_HASH=$(cast send "$BRIDGE" "requestNewWallet()" \
    --rpc-url "$RPC_URL" \
    --unlocked \
    --from "$ACCOUNT" \
    --gas-limit 500000 \
    2>&1 | grep -E "transactionHash|0x[a-fA-F0-9]{64}" | head -1 | grep -oE "0x[a-fA-F0-9]{64}" || echo "")

if [ -z "$TX_HASH" ]; then
    echo "Error: Failed to get transaction hash"
    echo ""
    echo "Trying alternative method..."
    # Try without --unlocked flag
    cast send "$BRIDGE" "requestNewWallet()" \
        --rpc-url "$RPC_URL" \
        --from "$ACCOUNT" \
        --gas-limit 500000 \
        --gas-price 1000000000 || {
        echo ""
        echo "Transaction failed. Possible issues:"
        echo "  1. Account not unlocked in Geth"
        echo "  2. Account doesn't have enough ETH"
        echo "  3. Bridge or WalletRegistry configuration issue"
        echo ""
        echo "Try manually:"
        echo "  geth attach http://localhost:8545"
        echo "  > personal.unlockAccount(eth.accounts[0], \"$KEEP_ETHEREUM_PASSWORD\", 0)"
        echo "  > eth.sendTransaction({from: eth.accounts[0], to: \"$BRIDGE\", data: \"0x72cc8c6d\", gas: 500000})"
        exit 1
    }
    TX_HASH=$(cast tx-pending --rpc-url "$RPC_URL" 2>/dev/null | head -1 | grep -oE "0x[a-fA-F0-9]{64}" || echo "")
fi

if [ -n "$TX_HASH" ]; then
    echo "✓ Transaction submitted: $TX_HASH"
    echo ""
    echo "Checking transaction status (non-blocking)..."
    
    # Try to get receipt immediately (non-blocking)
    RECEIPT_JSON=$(timeout 5 cast receipt "$TX_HASH" --rpc-url "$RPC_URL" --json 2>/dev/null || echo "")
    
    if [ -z "$RECEIPT_JSON" ] || [ "$RECEIPT_JSON" = "" ]; then
        echo "⚠️  Transaction receipt not immediately available"
        echo "   Transaction hash: $TX_HASH"
        echo "   This is normal - transaction may still be pending or mining"
        echo ""
        echo "The transaction has been submitted successfully."
        echo "You can check its status manually:"
        echo ""
        echo "  # Check receipt:"
        echo "  cast receipt $TX_HASH --rpc-url $RPC_URL"
        echo ""
        echo "  # Or check in Geth console:"
        echo "  geth attach http://localhost:8545"
        echo "  > eth.getTransactionReceipt(\"$TX_HASH\")"
        echo ""
        echo "  # Or check transaction:"
        echo "  cast tx $TX_HASH --rpc-url $RPC_URL"
        echo ""
        echo "Once confirmed, you can monitor DKG progress in node logs."
        exit 0
    fi
    
    # Parse receipt
    STATUS=$(echo "$RECEIPT_JSON" | jq -r '.status' 2>/dev/null || echo "")
    BLOCK=$(echo "$RECEIPT_JSON" | jq -r '.blockNumber' 2>/dev/null || echo "")
    
    if [ "$STATUS" = "1" ] || [ "$STATUS" = "0x1" ] || [ "$STATUS" = "0x01" ]; then
        echo "✓ Transaction confirmed in block: $BLOCK"
        echo ""
        echo "=========================================="
        echo "DKG Request Complete!"
        echo "=========================================="
        echo ""
        echo "You can monitor DKG progress in node logs"
    elif [ "$STATUS" = "0" ] || [ "$STATUS" = "0x0" ] || [ "$STATUS" = "0x00" ]; then
        echo "⚠️  Transaction reverted (status: 0)"
        echo "   Block: $BLOCK"
        echo ""
        echo "Check the revert reason:"
        echo "  cast run $TX_HASH --rpc-url $RPC_URL --trace"
        exit 1
    else
        echo "⚠️  Could not determine transaction status"
        echo "   Transaction hash: $TX_HASH"
        echo "   Block: $BLOCK"
        echo "   Status: $STATUS"
        echo ""
        echo "Check manually: cast receipt $TX_HASH --rpc-url $RPC_URL"
    fi
else
    echo "Error: Could not submit transaction"
    exit 1
fi

