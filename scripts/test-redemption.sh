#!/bin/bash
# Quick test script for redemption
# This uses existing wallet and dummy Bitcoin script for testing

set -e

RPC_URL="${RPC_URL:-http://localhost:8545}"
BRIDGE="${BRIDGE_ADDRESS:-0x7C1Aeaa16b0e4C491105E061748A08cbD663d113}"
WALLET_REGISTRY="${WALLET_REGISTRY:-0xd49141e044801DEE237993deDf9684D59fafE2e6}"

echo "=========================================="
echo "Test Redemption Request"
echo "=========================================="
echo ""

# Get first available account
FROM=$(cast rpc eth_accounts --rpc-url $RPC_URL 2>/dev/null | jq -r '.[0]')
echo "From account: $FROM"
echo ""

# Find an existing wallet
echo "Looking for existing wallets..."
WALLET_EVENT=$(cast logs --from-block 0 --to-block latest \
    "WalletCreated(bytes32 walletID, bytes32 dkgResultHash)" \
    --address $WALLET_REGISTRY \
    --rpc-url $RPC_URL 2>/dev/null | tail -20)

if [ -z "$WALLET_EVENT" ]; then
    echo "No wallets found. Please create a wallet first via DKG."
    exit 1
fi

# Extract wallet ID from the last wallet created
WALLET_ID=$(echo "$WALLET_EVENT" | grep -A1 "topics:" | tail -1 | tr -d ' \t' | grep "0x" | head -1)

if [ -z "$WALLET_ID" ]; then
    echo "Could not parse wallet ID"
    exit 1
fi

echo "Using wallet ID: $WALLET_ID"

# Get wallet public key
PUBKEY=$(cast call $WALLET_REGISTRY "getWalletPublicKey(bytes32)(bytes)" "$WALLET_ID" --rpc-url $RPC_URL 2>/dev/null)
echo "Wallet public key: ${PUBKEY:0:50}..."

if [ -z "$PUBKEY" ] || [ "$PUBKEY" = "0x" ]; then
    echo "Could not get wallet public key"
    exit 1
fi

# Calculate pubkey hash (simplified - use first 20 bytes for testing)
# In reality, this should be HASH160(compressed_pubkey)
# For testing, we'll use a known wallet pubkey hash from diagnostics
echo ""
echo "Known wallet public key hashes (from node diagnostics):"
echo "  - 0x9850b965a0ef404ce03dd88691201cc537beaefd"
echo "  - 0x49be77e65eaa59efe636c5757fd3c31fc5efbb66"
echo "  - 0xfed577fbba8e72ec01810e12b09d974d7ef6b6bf"
echo ""

# Use first known wallet for testing
WALLET_PUBKEY_HASH="0x9850b965a0ef404ce03dd88691201cc537beaefd"
echo "Using wallet pubkey hash: $WALLET_PUBKEY_HASH"

# Check if wallet is registered in Bridge
echo ""
echo "Checking wallet in Bridge..."
WALLET_STATE=$(cast call $BRIDGE "wallets(bytes20)" "$WALLET_PUBKEY_HASH" --rpc-url $RPC_URL 2>&1)
echo "Wallet state: ${WALLET_STATE:0:100}..."

# Generate a dummy P2PKH redeemer script
# Format: OP_DUP OP_HASH160 <20-byte-hash> OP_EQUALVERIFY OP_CHECKSIG
# 76 a9 14 <hash> 88 ac
DUMMY_HASH="0000000000000000000000000000000000000001"  # Dummy hash for testing
REDEEMER_SCRIPT="0x76a914${DUMMY_HASH}88ac"
echo ""
echo "Using dummy P2PKH script: $REDEEMER_SCRIPT"

# Amount in satoshis (0.001 BTC = 100,000 satoshis)
AMOUNT=100000
echo "Amount: $AMOUNT satoshis (0.001 BTC)"

# Main UTXO (empty for testing - wallet needs actual UTXO)
MAIN_UTXO="(0x0000000000000000000000000000000000000000000000000000000000000000,0,0)"

echo ""
echo "=========================================="
echo "Sending redemption request..."
echo "=========================================="
echo ""

# Try to send the transaction
TX_RESULT=$(cast send $BRIDGE \
    "requestRedemption(bytes20,(bytes32,uint32,uint64),bytes,uint64)" \
    "$WALLET_PUBKEY_HASH" \
    "$MAIN_UTXO" \
    "$REDEEMER_SCRIPT" \
    "$AMOUNT" \
    --rpc-url $RPC_URL \
    --unlocked \
    --from $FROM \
    2>&1) || true

echo "$TX_RESULT"
echo ""

if echo "$TX_RESULT" | grep -qi "success\|transactionHash"; then
    echo "✓ Redemption request sent!"
    echo ""
    echo "Check for RedemptionRequested events:"
    cast logs --from-block latest --to-block latest \
        --address $BRIDGE \
        --rpc-url $RPC_URL 2>/dev/null | head -30
else
    echo "✗ Transaction may have failed"
    echo ""
    echo "Common issues:"
    echo "  1. Wallet not registered in Bridge (need to call __ecdsaWalletCreatedCallback)"
    echo "  2. Wallet doesn't have a main UTXO"
    echo "  3. Wallet not in 'Live' state"
    echo ""
    echo "To register wallet in Bridge, the WalletRegistry needs to call"
    echo "Bridge.__ecdsaWalletCreatedCallback() when wallet is created."
fi
