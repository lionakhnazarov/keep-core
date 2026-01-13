#!/bin/bash
set -e

# Speed up block production by sending transactions
# Clique consensus only produces blocks when there are transactions in the mempool

RPC_URL="http://localhost:8545"

echo "=========================================="
echo "Speeding Up Block Production"
echo "=========================================="
echo ""

# Get current block
CURRENT_BLOCK=$(cast block-number --rpc-url $RPC_URL 2>/dev/null | xargs cast --to-dec 2>/dev/null)

# Calculate next coordination window
COORDINATION_FREQUENCY=900
NEXT_WINDOW=$((((CURRENT_BLOCK / COORDINATION_FREQUENCY) + 1) * COORDINATION_FREQUENCY))
BLOCKS_NEEDED=$((NEXT_WINDOW - CURRENT_BLOCK))

echo "Current block:           $CURRENT_BLOCK"
echo "Next coordination window: $NEXT_WINDOW"
echo "Blocks needed:           $BLOCKS_NEEDED"
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

# Check if account needs to be unlocked
echo "Sending transactions to trigger block production..."
echo "This will send $BLOCKS_NEEDED transactions to trigger blocks"
echo ""

START_BLOCK=$CURRENT_BLOCK
SUCCESS=0
FAILED=0

for i in $(seq 1 $BLOCKS_NEEDED); do
    # Send zero-value transaction to self
    if cast send --from $FROM_ACCOUNT --value 0 $FROM_ACCOUNT \
        --rpc-url $RPC_URL \
        --unlocked \
        --gas-limit 21000 \
        --gas-price 1000000000 \
        2>/dev/null > /dev/null; then
        SUCCESS=$((SUCCESS + 1))
    else
        FAILED=$((FAILED + 1))
        if [ $FAILED -eq 1 ]; then
            echo "⚠️  Transaction failed. Account may need to be unlocked."
            echo ""
            echo "To unlock account, run:"
            echo "  geth attach http://localhost:8545"
            echo "  personal.unlockAccount('$FROM_ACCOUNT', 'password', 0)"
            echo ""
            echo "Or use the password from your geth startup command."
            echo ""
            echo "Continuing anyway (some transactions may fail)..."
            echo ""
        fi
    fi
    
    # Small delay to avoid overwhelming
    sleep 0.1
    
    # Check progress every 10 transactions
    if [ $((i % 10)) -eq 0 ]; then
        NEW_BLOCK=$(cast block-number --rpc-url $RPC_URL 2>/dev/null | xargs cast --to-dec 2>/dev/null)
        BLOCKS_MINED=$((NEW_BLOCK - START_BLOCK))
        printf "\r  Sent %d transactions | Blocks mined: %d/%d" $i $BLOCKS_MINED $BLOCKS_NEEDED
        
        # If we've mined enough blocks, we can stop
        if [ $BLOCKS_MINED -ge $BLOCKS_NEEDED ]; then
            break
        fi
    fi
done

echo ""
echo ""

FINAL_BLOCK=$(cast block-number --rpc-url $RPC_URL 2>/dev/null | xargs cast --to-dec 2>/dev/null)
echo "✅ Complete!"
echo "   Transactions sent: $SUCCESS successful, $FAILED failed"
echo "   Final block: $FINAL_BLOCK"
echo ""

# Check if we reached coordination window
if [ $FINAL_BLOCK -ge $NEXT_WINDOW ]; then
    echo "🎉 Reached coordination window at block $NEXT_WINDOW!"
    echo "   Deposit sweep should proceed now."
else
    REMAINING=$((NEXT_WINDOW - FINAL_BLOCK))
    echo "   Still need $REMAINING more blocks"
    echo "   Blocks are being produced automatically, but slowly."
    echo "   You can run this script again or wait."
fi

