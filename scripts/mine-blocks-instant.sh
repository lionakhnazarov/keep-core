#!/bin/bash
set -e

# Script to instantly mine blocks using evm_mine (works with Hardhat/Anvil)
# For Geth with Clique PoA, this will try evm_mine but may not work
# In that case, blocks will be produced at the fixed period rate

RPC_URL="http://localhost:8545"

echo "=========================================="
echo "Instant Block Mining"
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

# Try evm_mine (works with Hardhat/Anvil, not with Geth)
echo "Attempting to use evm_mine for instant block production..."
echo ""

START_BLOCK=$CURRENT_BLOCK
SUCCESS=0
FAILED=0

for i in $(seq 1 $BLOCKS_NEEDED); do
    if cast rpc evm_mine --rpc-url $RPC_URL 2>/dev/null > /dev/null; then
        SUCCESS=$((SUCCESS + 1))
        
        # Check progress every 50 blocks
        if [ $((i % 50)) -eq 0 ] || [ $i -eq $BLOCKS_NEEDED ]; then
            CURRENT_BLOCK=$(cast block-number --rpc-url $RPC_URL 2>/dev/null | xargs cast --to-dec 2>/dev/null)
            BLOCKS_MINED=$((CURRENT_BLOCK - START_BLOCK))
            REMAINING=$((NEXT_WINDOW - CURRENT_BLOCK))
            printf "\r  Mined %d blocks | Current: %d | Remaining: %d" $BLOCKS_MINED $CURRENT_BLOCK $REMAINING
            
            if [ $CURRENT_BLOCK -ge $NEXT_WINDOW ]; then
                break
            fi
        fi
    else
        FAILED=$((FAILED + 1))
        if [ $FAILED -eq 1 ]; then
            echo ""
            echo "⚠️  evm_mine not available (expected with Geth/Clique PoA)"
            echo ""
            echo "With Geth and Clique PoA, blocks are produced at fixed intervals."
            echo "To speed up blocks, you need to restart Geth with a faster period:"
            echo ""
            echo "1. Stop current Geth:"
            echo "   pkill -f 'geth.*8545'"
            echo ""
            echo "2. Restart with faster block period (0.1 seconds):"
            echo "   BLOCK_PERIOD=0.1 ./scripts/start-geth-fast.sh"
            echo ""
            echo "Or wait for blocks to be produced naturally (~$BLOCKS_NEEDED seconds)..."
            echo ""
            echo "Continuing to wait for blocks..."
            echo ""
            break
        fi
    fi
done

echo ""
echo ""

FINAL_BLOCK=$(cast block-number --rpc-url $RPC_URL 2>/dev/null | xargs cast --to-dec 2>/dev/null)
echo "✅ Complete!"
echo "   Blocks mined instantly: $SUCCESS"
echo "   Failed attempts: $FAILED"
echo "   Final block: $FINAL_BLOCK"
echo ""

# Check if we reached coordination window
if [ $FINAL_BLOCK -ge $NEXT_WINDOW ]; then
    echo "🎉 Reached coordination window at block $NEXT_WINDOW!"
else
    REMAINING=$((NEXT_WINDOW - FINAL_BLOCK))
    echo "   Still need $REMAINING more blocks"
    if [ $FAILED -gt 0 ]; then
        echo ""
        echo "💡 Tip: Restart Geth with faster block period for instant mining:"
        echo "   BLOCK_PERIOD=0.1 ./scripts/start-geth-fast.sh"
    fi
fi

