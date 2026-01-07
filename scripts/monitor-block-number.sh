#!/bin/bash
# Script to monitor local geth block number

set -e

RPC_URL="${RPC_URL:-http://localhost:8545}"
INTERVAL="${INTERVAL:-2}"  # Default to 2 seconds

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Monitoring Geth Block Number"
echo "=========================================="
echo "RPC URL: $RPC_URL"
echo "Update interval: ${INTERVAL}s"
echo "Press Ctrl+C to stop"
echo "=========================================="
echo ""

# Function to get block number
get_block_number() {
    local response=$(curl -s -X POST \
        -H 'Content-Type: application/json' \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$RPC_URL" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}[ERROR]${NC} Could not connect to geth at $RPC_URL" >&2
        return 1
    fi
    
    local block_hex=$(echo "$response" | grep -o '"result":"0x[0-9a-f]*"' | cut -d'"' -f4)
    
    if [ -z "$block_hex" ]; then
        echo -e "${RED}[ERROR]${NC} Invalid response from geth" >&2
        echo "Response: $response" >&2
        return 1
    fi
    
    # Convert hex to decimal
    local block_decimal=$(printf "%d" "$block_hex")
    echo "$block_decimal"
    return 0
}

# Initialize tracking variables
last_block=0
last_block_time=0
start_time=$(date +%s)
blocks_seen=0
stuck_count=0
block_times=()

# Monitor loop
while true; do
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    current_time=$(date +%s)
    current_block=$(get_block_number)
    
    if [ $? -eq 0 ]; then
        if [ "$last_block" -eq 0 ]; then
            # First block seen
            echo -e "${CYAN}[$timestamp]${NC} Initial block: ${GREEN}$current_block${NC}"
            last_block=$current_block
            last_block_time=$current_time
            blocks_seen=1
            block_times+=($current_time)
        elif [ "$current_block" -gt "$last_block" ]; then
            # New block detected
            block_diff=$((current_block - last_block))
            time_diff=$((current_time - last_block_time))
            
            # Calculate block rate
            if [ $time_diff -gt 0 ]; then
                block_rate=$(echo "scale=2; $block_diff / $time_diff" | bc 2>/dev/null || echo "0")
                if [ -n "$block_rate" ] && [ "$block_rate" != "0" ]; then
                    rate_str="(${block_rate} blk/s)"
                else
                    rate_str=""
                fi
            else
                rate_str=""
            fi
            
            # Calculate time since last block
            if [ $time_diff -lt 60 ]; then
                time_str="${time_diff}s ago"
            elif [ $time_diff -lt 3600 ]; then
                time_str="$((time_diff / 60))m ${time_diff}s ago"
            else
                time_str="$((time_diff / 3600))h $((time_diff % 3600 / 60))m ago"
            fi
            
            echo -e "${GREEN}[$timestamp]${NC} Block: ${CYAN}$current_block${NC} ${GREEN}(+$block_diff)${NC} ${BLUE}$time_str${NC} $rate_str"
            
            last_block=$current_block
            last_block_time=$current_time
            blocks_seen=$((blocks_seen + block_diff))
            stuck_count=0
            
            # Keep last 10 block times for rate calculation
            block_times+=($current_time)
            if [ ${#block_times[@]} -gt 10 ]; then
                block_times=("${block_times[@]:1}")
            fi
        elif [ "$current_block" -eq "$last_block" ]; then
            # Block hasn't changed
            stuck_count=$((stuck_count + 1))
            time_since_last=$((current_time - last_block_time))
            
            if [ $time_since_last -gt 30 ]; then
                # Warn if stuck for more than 30 seconds
                echo -e "${YELLOW}[$timestamp]${NC} Block: ${CYAN}$current_block${NC} ${RED}(STUCK for ${time_since_last}s)${NC}"
            else
                echo -e "[$timestamp] Block: ${CYAN}$current_block${NC} (no change, ${time_since_last}s)"
            fi
        fi
        
        # Show summary every 10 checks
        if [ $((stuck_count % 10)) -eq 0 ] && [ $stuck_count -gt 0 ]; then
            elapsed=$((current_time - start_time))
            if [ $elapsed -gt 0 ] && [ $blocks_seen -gt 0 ]; then
                avg_rate=$(echo "scale=4; $blocks_seen / $elapsed" | bc 2>/dev/null || echo "0")
                echo -e "${BLUE}--- Summary: ${blocks_seen} blocks in ${elapsed}s (avg: ${avg_rate} blk/s) ---${NC}"
            fi
        fi
    else
        stuck_count=$((stuck_count + 1))
    fi
    
    sleep "$INTERVAL"
done

