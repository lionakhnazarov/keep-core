#!/bin/bash

# Script to measure redemption speed from node logs
# Usage: ./scripts/measure-redemption-speed.sh [log_file] [options]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default log file
LOG_FILE="${1:-logs/node1.log}"

# Check if log file exists
if [ ! -f "$LOG_FILE" ]; then
    echo -e "${RED}Error: Log file not found: $LOG_FILE${NC}" >&2
    exit 1
fi

echo -e "${BLUE}=== Redemption Speed Analysis ===${NC}"
echo "Log file: $LOG_FILE"
echo ""

# Function to parse timestamp and convert to epoch
parse_timestamp() {
    local ts="$1"
    # Format: 2026-01-07T16:26:37.359Z
    # Try macOS format first, then Linux format
    if date -j -f "%Y-%m-%dT%H:%M:%S" "${ts%.*}" "+%s" 2>/dev/null; then
        return
    elif date -d "${ts%.*}" "+%s" 2>/dev/null; then
        return
    else
        echo "0"
    fi
}

# Extract redemption actions
echo -e "${YELLOW}Extracting redemption actions...${NC}"

# Find all redemption action starts
REDEMPTION_STARTS=$(grep -E "starting orchestration of the redemption action|dispatching wallet action.*redemption" "$LOG_FILE" | \
    grep -v "deposit\|sweep\|moving" || true)

if [ -z "$REDEMPTION_STARTS" ]; then
    echo -e "${YELLOW}No redemption actions found in logs${NC}"
    exit 0
fi

# Process each redemption
declare -a REDEMPTION_DATA

while IFS= read -r line; do
    # Extract timestamp
    timestamp=$(echo "$line" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z' | head -1)
    
    # Extract wallet address
    wallet=$(echo "$line" | grep -oE '0x[0-9a-fA-F]{64}' | head -1 || echo "unknown")
    
    if [ -n "$timestamp" ] && [ -n "$wallet" ]; then
        REDEMPTION_DATA+=("$timestamp|$wallet")
    fi
done <<< "$REDEMPTION_STARTS"

if [ ${#REDEMPTION_DATA[@]} -eq 0 ]; then
    echo -e "${YELLOW}No valid redemption data found${NC}"
    exit 0
fi

echo -e "${GREEN}Found ${#REDEMPTION_DATA[@]} redemption action(s)${NC}"
echo ""

# Process each redemption to extract step timings
for redemption in "${REDEMPTION_DATA[@]}"; do
    IFS='|' read -r start_time wallet <<< "$redemption"
    
    echo -e "${BLUE}--- Redemption: ${wallet:0:16}... ---${NC}"
    echo "Start time: $start_time"
    
    # Find all log entries for this wallet and redemption action
    wallet_logs=$(grep -E "wallet.*$wallet|action.*redemption" "$LOG_FILE" | \
        grep -E "step|action execution|redemption" || true)
    
    if [ -z "$wallet_logs" ]; then
        echo -e "${YELLOW}  No detailed logs found for this redemption${NC}"
        echo ""
        continue
    fi
    
    # Extract step timings
    validate_start=""
    validate_end=""
    sign_start=""
    sign_end=""
    broadcast_start=""
    broadcast_end=""
    action_end=""
    
    while IFS= read -r log_line; do
        timestamp=$(echo "$log_line" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z' | head -1)
        
        if [[ "$log_line" =~ "step.*validateProposal" ]]; then
            if [ -z "$validate_start" ]; then
                validate_start="$timestamp"
            fi
        elif [[ "$log_line" =~ "step.*signTransaction" ]]; then
            if [ -n "$validate_start" ] && [ -z "$validate_end" ]; then
                validate_end="$timestamp"
            fi
            if [ -z "$sign_start" ]; then
                sign_start="$timestamp"
            fi
        elif [[ "$log_line" =~ "step.*broadcastTransaction" ]]; then
            if [ -n "$sign_start" ] && [ -z "$sign_end" ]; then
                sign_end="$timestamp"
            fi
            if [ -z "$broadcast_start" ]; then
                broadcast_start="$timestamp"
            fi
        elif [[ "$log_line" =~ "action execution terminated" ]]; then
            if [ -n "$broadcast_start" ] && [ -z "$broadcast_end" ]; then
                broadcast_end="$timestamp"
            fi
            action_end="$timestamp"
        fi
    done <<< "$wallet_logs"
    
    # Calculate durations
    if [ -n "$start_time" ] && [ -n "$action_end" ]; then
        start_epoch=$(parse_timestamp "$start_time")
        end_epoch=$(parse_timestamp "$action_end")
        
        if [ "$start_epoch" != "0" ] && [ "$end_epoch" != "0" ]; then
            total_duration=$((end_epoch - start_epoch))
            echo -e "${GREEN}  Total duration: ${total_duration}s${NC}"
        fi
    fi
    
    # Display step durations
    if [ -n "$validate_start" ] && [ -n "$validate_end" ]; then
        val_start_epoch=$(parse_timestamp "$validate_start")
        val_end_epoch=$(parse_timestamp "$validate_end")
        if [ "$val_start_epoch" != "0" ] && [ "$val_end_epoch" != "0" ]; then
            val_duration=$((val_end_epoch - val_start_epoch))
            echo "  Validation: ${val_duration}s"
        fi
    fi
    
    if [ -n "$sign_start" ] && [ -n "$sign_end" ]; then
        sign_start_epoch=$(parse_timestamp "$sign_start")
        sign_end_epoch=$(parse_timestamp "$sign_end")
        if [ "$sign_start_epoch" != "0" ] && [ "$sign_end_epoch" != "0" ]; then
            sign_duration=$((sign_end_epoch - sign_start_epoch))
            echo "  Signing: ${sign_duration}s"
        fi
    fi
    
    if [ -n "$broadcast_start" ] && [ -n "$broadcast_end" ]; then
        bc_start_epoch=$(parse_timestamp "$broadcast_start")
        bc_end_epoch=$(parse_timestamp "$broadcast_end")
        if [ "$bc_start_epoch" != "0" ] && [ "$bc_end_epoch" != "0" ]; then
            bc_duration=$((bc_end_epoch - bc_start_epoch))
            echo "  Broadcast: ${bc_duration}s"
        fi
    fi
    
    echo ""
done

# Summary statistics
echo -e "${BLUE}=== Summary ===${NC}"

# Count successful redemptions
success_count=$(grep -c "action execution terminated with success.*redemption" "$LOG_FILE" 2>/dev/null || echo "0")
failed_count=$(grep -c "action execution terminated with error.*redemption" "$LOG_FILE" 2>/dev/null || echo "0")

echo "Successful redemptions: $success_count"
echo "Failed redemptions: $failed_count"

if [ $((success_count + failed_count)) -gt 0 ]; then
    success_rate=$(echo "scale=2; $success_count * 100 / ($success_count + $failed_count)" | bc)
    echo "Success rate: ${success_rate}%"
fi

echo ""
echo -e "${GREEN}Analysis complete!${NC}"

