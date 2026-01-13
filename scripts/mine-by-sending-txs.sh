#!/bin/bash
set -e

# Mine blocks by sending transactions (works when miner module not available)
# This triggers block production by sending transactions

RPC_URL="http://localhost:8545"

# Get current block
CURRENT_BLOCK=$(cast block-number --rpc-url $RPC_URL 2>/dev/null | xargs cast --to-dec 2>/dev/null)

# Calculate next coordination window
COORDINATION_FREQUENCY=900
NEXT_WINDOW=$((((CURRENT_BLOCK / COORDINATION_FREQUENCY) + 1) * COORDINATION_FREQUENCY))
BLOCKS_NEEDED=$((NEXT_WINDOW - CURRENT_BLOCK))

# Use provided number or calculate automatically
if [ -n "$1" ]; then
    BLOCKS_TO_MINE=$1
else
    BLOCKS_TO_MINE=$BLOCKS_NEEDED
fi

echo "=========================================="
echo "Mining Blocks by Sending Transactions"
echo "=========================================="
echo ""
echo "Current block:           $CURRENT_BLOCK"
echo "Next coordination window: $NEXT_WINDOW"
echo "Blocks to mine:          $BLOCKS_TO_MINE"
echo ""

# Get an account
ACCOUNTS=$(cast rpc eth_accounts --rpc-url $RPC_URL 2>/dev/null | jq -r '.[]' || echo "")
if [ -z "$ACCOUNTS" ]; then
    echo "❌ Error: No accounts found"
    exit 1
fi

FROM_ACCOUNT=$(echo "$ACCOUNTS" | head -1)
echo "Using account: $FROM_ACCOUNT"
echo ""

# Check if account is unlocked
echo "Sending transactions to trigger block production..."
echo ""

START_BLOCK=$CURRENT_BLOCK
BLOCKS_MINED=0

# Send transactions to trigger block production
for i in $(seq 1 $BLOCKS_TO_MINE); do
    # Send a zero-value transaction to self to trigger block
    cast send --from $FROM_ACCOUNT --value 0 $FROM_ACCOUNT \
        --rpc-url $RPC_URL \
        --unlocked \
        --gas-limit 21000 \
        --gas-price 1000000000 \
        2>/dev/null || {
        echo "⚠️  Transaction failed. Account may need to be unlocked."
        echo ""
        echo "To unlock account, run:"
        echo "  geth attach http://localhost:8545"
        echo "  personal.unlockAccount('$FROM_ACCOUNT', 'password', 0)"
        echo ""
        exit 1
    }
    
    # Wait a bit for block to be mined
    sleep 0.5
    
    # Check progress
    NEW_BLOCK=$(cast block-number --rpc-url $RPC_URL 2>/dev/null | xargs cast --to-dec 2>/dev/null)
    BLOCKS_MINED=$((NEW_BLOCK - START_BLOCK))
    
    if [ $((i % 10)) -eq 0 ] || [ $BLOCKS_MINED -ge $BLOCKS_TO_MINE ]; then
        printf "\r  Progress: Block %d (%d/%d mined)" $NEW_BLOCK $BLOCKS_MINED $BLOCKS_TO_MINE
    fi
    
    if [ $BLOCKS_MINED -ge $BLOCKS_TO_MINE ]; then
        break
    fi
done

echo ""
echo ""

FINAL_BLOCK=$(cast block-number --rpc-url $RPC_URL 2>/dev/null | xargs cast --to-dec 2>/dev/null)
echo "✅ Complete!"
echo "   Final block: $FINAL_BLOCK"
echo ""

# Check if we reached coordination window
if [ $FINAL_BLOCK -ge $NEXT_WINDOW ]; then
    echo "🎉 Reached coordination window at block $NEXT_WINDOW!"
    echo "   Deposit sweep should proceed now."
else
    REMAINING=$((NEXT_WINDOW - FINAL_BLOCK))
    echo "   Still need $REMAINING more blocks to reach coordination window"
fi

