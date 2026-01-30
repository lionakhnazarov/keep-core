#!/bin/bash

# Monitor coordination windows in realtime
# Shows when the next coordination window will occur

RPC_URL="${RPC_URL:-http://localhost:8545}"
COORDINATION_FREQUENCY=300
REFRESH_INTERVAL=2

echo "=========================================="
echo "Coordination Window Monitor"
echo "=========================================="
echo "RPC: $RPC_URL"
echo "Window frequency: Every $COORDINATION_FREQUENCY blocks"
echo "Press Ctrl+C to exit"
echo ""

# Track for block rate calculation
FIRST_BLOCK=""
FIRST_TIME=""

while true; do
    # Get current block
    CURRENT_BLOCK=$(cast block-number --rpc-url $RPC_URL 2>/dev/null | xargs cast --to-dec 2>/dev/null)
    
    if [ -z "$CURRENT_BLOCK" ]; then
        echo "⚠️  Cannot connect to RPC at $RPC_URL"
        sleep $REFRESH_INTERVAL
        continue
    fi
    
    NOW=$(date +%s)
    
    # Initialize tracking on first run
    if [ -z "$FIRST_BLOCK" ]; then
        FIRST_BLOCK=$CURRENT_BLOCK
        FIRST_TIME=$NOW
    fi
    
    # Calculate window info
    CURRENT_WINDOW_INDEX=$((CURRENT_BLOCK / COORDINATION_FREQUENCY))
    CURRENT_WINDOW_START=$((CURRENT_WINDOW_INDEX * COORDINATION_FREQUENCY))
    NEXT_WINDOW_START=$(((CURRENT_WINDOW_INDEX + 1) * COORDINATION_FREQUENCY))
    BLOCKS_REMAINING=$((NEXT_WINDOW_START - CURRENT_BLOCK))
    BLOCKS_INTO_WINDOW=$((CURRENT_BLOCK - CURRENT_WINDOW_START))
    
    # Active phase ends at start + 80 blocks
    ACTIVE_PHASE_END=$((CURRENT_WINDOW_START + 80))
    # Window ends at start + 100 blocks
    WINDOW_END=$((CURRENT_WINDOW_START + 100))
    
    # Determine if we're in a window
    IN_ACTIVE_PHASE="no"
    IN_PASSIVE_PHASE="no"
    if [ $BLOCKS_INTO_WINDOW -lt 80 ]; then
        IN_ACTIVE_PHASE="yes"
    elif [ $BLOCKS_INTO_WINDOW -lt 100 ]; then
        IN_PASSIVE_PHASE="yes"
    fi
    
    # Calculate block rate (blocks per second)
    ELAPSED=$((NOW - FIRST_TIME))
    BLOCKS_MINED=$((CURRENT_BLOCK - FIRST_BLOCK))
    
    if [ $ELAPSED -gt 5 ] && [ $BLOCKS_MINED -gt 0 ]; then
        # Use bc for floating point
        BLOCK_RATE=$(echo "scale=2; $BLOCKS_MINED / $ELAPSED" | bc 2>/dev/null || echo "0")
        if [ "$BLOCK_RATE" != "0" ] && [ -n "$BLOCK_RATE" ]; then
            ETA_SECONDS=$(echo "scale=0; $BLOCKS_REMAINING / $BLOCK_RATE" | bc 2>/dev/null || echo "0")
            if [ -n "$ETA_SECONDS" ] && [ "$ETA_SECONDS" != "" ]; then
                ETA_MIN=$((ETA_SECONDS / 60))
                ETA_SEC=$((ETA_SECONDS % 60))
                ETA_STR="${ETA_MIN}m ${ETA_SEC}s"
            else
                ETA_STR="calculating..."
            fi
        else
            ETA_STR="calculating..."
        fi
    else
        BLOCK_RATE="--"
        ETA_STR="calculating..."
    fi
    
    # Clear screen and display
    clear
    echo "=========================================="
    echo "🔄 Coordination Window Monitor"
    echo "=========================================="
    echo ""
    echo "📊 Current Status"
    echo "   Block:          $CURRENT_BLOCK"
    echo "   Window Index:   $CURRENT_WINDOW_INDEX"
    echo "   Block Rate:     $BLOCK_RATE blocks/sec"
    echo ""
    
    # Show window status
    if [ "$IN_ACTIVE_PHASE" = "yes" ]; then
        BLOCKS_LEFT=$((80 - BLOCKS_INTO_WINDOW))
        echo "🟢 IN ACTIVE PHASE NOW!"
        echo "   Window started at block: $CURRENT_WINDOW_START"
        echo "   Active phase ends at:    $ACTIVE_PHASE_END ($BLOCKS_LEFT blocks left)"
        echo "   Window ends at:          $WINDOW_END"
    elif [ "$IN_PASSIVE_PHASE" = "yes" ]; then
        BLOCKS_LEFT=$((100 - BLOCKS_INTO_WINDOW))
        echo "🟡 IN PASSIVE PHASE"
        echo "   Window started at block: $CURRENT_WINDOW_START"
        echo "   Window ends at:          $WINDOW_END ($BLOCKS_LEFT blocks left)"
        echo "   Next window at:          $NEXT_WINDOW_START"
    else
        echo "⏳ Between Windows"
        echo "   Last window ended at:    $WINDOW_END"
        echo "   Next window starts at:   $NEXT_WINDOW_START"
        echo "   Blocks remaining:        $BLOCKS_REMAINING"
        echo "   Estimated time:          $ETA_STR"
    fi
    
    echo ""
    echo "📅 Window Schedule"
    echo "   Previous window:  Block $((CURRENT_WINDOW_START - COORDINATION_FREQUENCY))"
    echo "   Current/Last:     Block $CURRENT_WINDOW_START (index $CURRENT_WINDOW_INDEX)"
    echo "   Next window:      Block $NEXT_WINDOW_START (index $((CURRENT_WINDOW_INDEX + 1)))"
    echo "   Following:        Block $(((CURRENT_WINDOW_INDEX + 2) * COORDINATION_FREQUENCY)) (index $((CURRENT_WINDOW_INDEX + 2)))"
    echo ""
    echo "📖 Window Phases (100 blocks total)"
    echo "   Active phase:   Blocks 0-79  (80 blocks) - Leader/follower communication"
    echo "   Passive phase:  Blocks 80-99 (20 blocks) - Validation & preparation"
    echo ""
    echo "Last updated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Press Ctrl+C to exit"
    
    sleep $REFRESH_INTERVAL
done
