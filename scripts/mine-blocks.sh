#!/bin/bash
set -e

# Script to mine blocks quickly to reach the next coordination window
# Usage: ./scripts/mine-blocks.sh [number_of_blocks]

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
echo "Mining Blocks to Reach Coordination Window"
echo "=========================================="
echo ""
echo "Current block:           $CURRENT_BLOCK"
echo "Next coordination window: $NEXT_WINDOW"
echo "Blocks to mine:          $BLOCKS_TO_MINE"
echo ""

# Check if geth is using Clique (PoA) consensus
echo "Checking consensus mechanism..."
CLIQUE_ENABLED=$(cast rpc clique_getSnapshot --rpc-url $RPC_URL 2>/dev/null | head -1 || echo "")

if [ -n "$CLIQUE_ENABLED" ]; then
    echo "✅ Detected Clique (PoA) consensus"
    echo ""
    echo "For Clique consensus, blocks are produced at fixed intervals."
    echo "To speed up block production, you can:"
    echo ""
    echo "1. Use geth console to control block production:"
    echo "   geth attach $RPC_URL"
    echo "   Then run: miner.start()"
    echo ""
    echo "2. Or use this script with cast to mine blocks:"
    echo ""
    
    # Try to mine blocks using cast
    echo "Attempting to mine $BLOCKS_TO_MINE blocks..."
    for i in $(seq 1 $BLOCKS_TO_MINE); do
        # Send a transaction to trigger block mining
        # First, get an account with balance
        ACCOUNT=$(cast rpc eth_accounts --rpc-url $RPC_URL 2>/dev/null | jq -r '.[0]' || echo "")
        
        if [ -n "$ACCOUNT" ] && [ "$ACCOUNT" != "null" ]; then
            # Send a transaction to trigger block production
            cast rpc evm_mine --rpc-url $RPC_URL 2>/dev/null || \
            cast rpc miner_start --rpc-url $RPC_URL 2>/dev/null || \
            echo "Block $i: Mining..."
            
            # Wait a bit for block to be mined
            sleep 0.1
        else
            echo "⚠️  Could not find account. Trying alternative method..."
            break
        fi
        
        # Show progress every 10 blocks
        if [ $((i % 10)) -eq 0 ]; then
            NEW_BLOCK=$(cast block-number --rpc-url $RPC_URL 2>/dev/null | xargs cast --to-dec 2>/dev/null)
            echo "  Progress: Block $NEW_BLOCK ($i/$BLOCKS_TO_MINE)"
        fi
    done
else
    echo "⚠️  Clique not detected. Trying standard mining methods..."
    echo ""
    
    # Try to start miner if not already running
    echo "Starting miner..."
    cast rpc miner_start --rpc-url $RPC_URL 2>/dev/null || echo "Miner may already be running"
    
    echo ""
    echo "Mining $BLOCKS_TO_MINE blocks..."
    echo "This may take some time depending on difficulty..."
    
    START_BLOCK=$CURRENT_BLOCK
    TARGET_BLOCK=$((CURRENT_BLOCK + BLOCKS_TO_MINE))
    
    while [ $CURRENT_BLOCK -lt $TARGET_BLOCK ]; do
        sleep 1
        CURRENT_BLOCK=$(cast block-number --rpc-url $RPC_URL 2>/dev/null | xargs cast --to-dec 2>/dev/null)
        MINED=$((CURRENT_BLOCK - START_BLOCK))
        echo "  Mined $MINED/$BLOCKS_TO_MINE blocks (current: $CURRENT_BLOCK)"
    done
fi

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

