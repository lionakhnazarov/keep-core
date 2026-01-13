#!/bin/bash
set -e

# Fast block mining script for geth with Clique consensus
# This script sends transactions to trigger block production

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
echo "Fast Block Mining"
echo "=========================================="
echo ""
echo "Current block:           $CURRENT_BLOCK"
echo "Next coordination window: $NEXT_WINDOW"
echo "Blocks to mine:          $BLOCKS_TO_MINE"
echo ""

# Get an account with balance
ACCOUNTS=$(cast rpc eth_accounts --rpc-url $RPC_URL 2>/dev/null | jq -r '.[]' || echo "")
if [ -z "$ACCOUNTS" ]; then
    echo "❌ Error: No accounts found"
    exit 1
fi

FROM_ACCOUNT=$(echo "$ACCOUNTS" | head -1)
echo "Using account: $FROM_ACCOUNT"
echo ""

# Check balance
BALANCE=$(cast balance $FROM_ACCOUNT --rpc-url $RPC_URL 2>/dev/null || echo "0")
echo "Account balance: $BALANCE wei"
echo ""

if [ "$BALANCE" = "0" ] || [ -z "$BALANCE" ]; then
    echo "⚠️  Warning: Account has no balance. Mining may not work."
    echo "   Try using geth attach to mine blocks instead."
    echo ""
fi

echo "Mining $BLOCKS_TO_MINE blocks by sending transactions..."
echo ""

START_BLOCK=$CURRENT_BLOCK
BLOCKS_MINED=0

# Method 1: Try using geth attach to mine blocks
echo "Method 1: Using geth attach to mine blocks..."
echo ""

# Create a temporary script for geth console
TEMP_SCRIPT=$(mktemp)
cat > $TEMP_SCRIPT << EOF
for (i = 0; i < $BLOCKS_TO_MINE; i++) {
    miner.start(1);
    admin.sleepBlocks(1);
    miner.stop();
}
EOF

echo "Executing geth console commands..."
geth attach $RPC_URL --exec "$(cat $TEMP_SCRIPT)" 2>/dev/null || {
    echo "⚠️  geth attach method failed. Trying alternative..."
    echo ""
    echo "Alternative: Manual block mining"
    echo "=================================="
    echo ""
    echo "Run this command in a separate terminal:"
    echo ""
    echo "  geth attach $RPC_URL"
    echo ""
    echo "Then in the geth console, run:"
    echo ""
    echo "  for (i = 0; i < $BLOCKS_TO_MINE; i++) {"
    echo "    miner.start(1);"
    echo "    admin.sleepBlocks(1);"
    echo "    miner.stop();"
    echo "  }"
    echo ""
    echo "Or simply:"
    echo "  miner.start(1)"
    echo ""
    echo "And let it mine until block $NEXT_WINDOW"
    echo ""
    
    # Try sending transactions as alternative
    echo "Attempting to mine by sending transactions..."
    for i in $(seq 1 $BLOCKS_TO_MINE); do
        # Send a zero-value transaction to trigger block mining
        cast send --from $FROM_ACCOUNT --value 0 $FROM_ACCOUNT --rpc-url $RPC_URL --unlocked 2>/dev/null || true
        
        sleep 0.5
        
        NEW_BLOCK=$(cast block-number --rpc-url $RPC_URL 2>/dev/null | xargs cast --to-dec 2>/dev/null)
        BLOCKS_MINED=$((NEW_BLOCK - START_BLOCK))
        
        if [ $((i % 10)) -eq 0 ] || [ $BLOCKS_MINED -ge $BLOCKS_TO_MINE ]; then
            echo "  Progress: Block $NEW_BLOCK ($BLOCKS_MINED/$BLOCKS_TO_MINE)"
        fi
        
        if [ $BLOCKS_MINED -ge $BLOCKS_TO_MINE ]; then
            break
        fi
    done
}

rm -f $TEMP_SCRIPT

FINAL_BLOCK=$(cast block-number --rpc-url $RPC_URL 2>/dev/null | xargs cast --to-dec 2>/dev/null)
echo ""
echo "✅ Mining complete!"
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
