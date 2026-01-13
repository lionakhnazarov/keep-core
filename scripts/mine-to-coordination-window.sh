#!/bin/bash
set -e

# Simple script to mine blocks until the next coordination window
# Supports both PoW (miner API) and Clique PoA (transaction-based)

RPC_URL="http://localhost:8545"
GETH_ATTACH="geth attach $RPC_URL"

echo "=========================================="
echo "Mining to Next Coordination Window"
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

if [ $BLOCKS_NEEDED -le 0 ]; then
    echo "✅ Already at or past coordination window!"
    exit 0
fi

# Save start block for progress tracking
START_BLOCK_SAVED=$CURRENT_BLOCK

# Check if evm_mine is available (Hardhat/Anvil)
echo "Checking for instant mining capability..."
EVM_MINE_AVAILABLE=$(cast rpc evm_mine --rpc-url $RPC_URL 2>/dev/null && echo "yes" || echo "no")

if [ "$EVM_MINE_AVAILABLE" = "yes" ]; then
    echo "✅ evm_mine available - using instant mining!"
    echo ""
    echo "Mining $BLOCKS_NEEDED blocks instantly..."
    
    for i in $(seq 1 $BLOCKS_NEEDED); do
        cast rpc evm_mine --rpc-url $RPC_URL 2>/dev/null > /dev/null || break
        
        if [ $((i % 50)) -eq 0 ]; then
            CURRENT_BLOCK=$(cast block-number --rpc-url $RPC_URL 2>/dev/null | xargs cast --to-dec 2>/dev/null)
            REMAINING=$((NEXT_WINDOW - CURRENT_BLOCK))
            printf "\r  Mined %d blocks | Current: %d | Remaining: %d" $i $CURRENT_BLOCK $REMAINING
            
            if [ $CURRENT_BLOCK -ge $NEXT_WINDOW ]; then
                break
            fi
        fi
    done
    echo ""
    echo ""
    TRANSACTION_PID=""
else
    echo "⚠️  evm_mine not available (using Geth with Clique PoA)"
    echo ""
    echo "With Clique PoA, blocks are produced at FIXED intervals (1 second)."
    echo "Sending transactions won't speed this up - blocks will still be produced"
    echo "at the configured period rate."
    echo ""
    MINUTES=$((BLOCKS_NEEDED / 60))
    SECONDS_REMAINING=$((BLOCKS_NEEDED % 60))
    echo "Estimated time: ~$BLOCKS_NEEDED seconds (${MINUTES}m ${SECONDS_REMAINING}s)"
    echo ""
    echo "💡 To speed up blocks, restart Geth with faster period:"
    echo "   1. Stop Geth: pkill -f 'geth.*8545'"
    echo "   2. Restart: BLOCK_PERIOD=0.1 ./scripts/start-geth-fast.sh"
    echo ""
    echo "Waiting for blocks to be produced at natural rate..."
    echo ""
    TRANSACTION_PID=""
fi

echo "Waiting for block $NEXT_WINDOW..."
echo ""

# Monitor block progress
while true; do
    sleep 2
    CURRENT_BLOCK=$(cast block-number --rpc-url $RPC_URL 2>/dev/null | xargs cast --to-dec 2>/dev/null)
    BLOCKS_MINED=$((CURRENT_BLOCK - START_BLOCK_SAVED))
    REMAINING=$((NEXT_WINDOW - CURRENT_BLOCK))
    
    echo "  Current block: $CURRENT_BLOCK (need $REMAINING more)"
    
    if [ $CURRENT_BLOCK -ge $NEXT_WINDOW ]; then
        echo ""
        echo "✅ Reached coordination window!"
        
        # Stop background transaction sending if running
        if [ -n "${TRANSACTION_PID:-}" ]; then
            echo "Stopping transaction sending..."
            kill $TRANSACTION_PID 2>/dev/null || true
        fi
        
        echo ""
        echo "🎉 Ready for deposit sweep!"
        break
    fi
done

# Clean up background process if still running
if [ -n "${TRANSACTION_PID:-}" ]; then
    kill $TRANSACTION_PID 2>/dev/null || true
fi

