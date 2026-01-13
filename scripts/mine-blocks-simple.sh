#!/bin/bash
set -e

# Simple script to mine blocks using geth attach
# Usage: ./scripts/mine-blocks-simple.sh [blocks_to_mine]

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
echo "Mining Blocks"
echo "=========================================="
echo ""
echo "Current block:           $CURRENT_BLOCK"
echo "Next coordination window: $NEXT_WINDOW"
echo "Blocks to mine:          $BLOCKS_TO_MINE"
echo ""

# Method 1: Use geth attach with pipe
echo "Starting miner..."
echo "miner.start(1)" | geth attach $RPC_URL 2>/dev/null || {
    echo "⚠️  Failed to start miner via pipe method"
    echo ""
    echo "Please run manually:"
    echo "  geth attach $RPC_URL"
    echo ""
    echo "Then in the console, type:"
    echo "  miner.start(1)"
    echo ""
    echo "To stop mining, type:"
    echo "  miner.stop()"
    echo ""
    exit 1
}

echo "✅ Miner started!"
echo ""
echo "Mining blocks... (this will continue until you stop it)"
echo ""

# Monitor progress
START_BLOCK=$CURRENT_BLOCK
while true; do
    sleep 2
    CURRENT_BLOCK=$(cast block-number --rpc-url $RPC_URL 2>/dev/null | xargs cast --to-dec 2>/dev/null)
    BLOCKS_MINED=$((CURRENT_BLOCK - START_BLOCK))
    REMAINING=$((NEXT_WINDOW - CURRENT_BLOCK))
    
    printf "\r  Current block: %d | Mined: %d | Remaining: %d" $CURRENT_BLOCK $BLOCKS_MINED $REMAINING
    
    if [ $CURRENT_BLOCK -ge $NEXT_WINDOW ]; then
        echo ""
        echo ""
        echo "✅ Reached coordination window at block $NEXT_WINDOW!"
        
        # Stop miner
        echo "Stopping miner..."
        echo "miner.stop()" | geth attach $RPC_URL 2>/dev/null || true
        
        echo ""
        echo "🎉 Ready for deposit sweep!"
        break
    fi
done

