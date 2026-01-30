#!/bin/bash
# Script to create a redemption request and monitor for redemption proposal creation
# Redemption proposals are automatically created by the coordination leader during coordination windows

set -e

cd "$(dirname "$0")/.."

# Default values
RPC_URL="${RPC_URL:-http://localhost:8545}"
COORDINATION_FREQUENCY=300  # Updated from 900 to 300
LOG_DIR="${LOG_DIR:-logs}"
MONITOR_DURATION="${MONITOR_DURATION:-600}"  # Monitor for 10 minutes by default

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Get Bridge address from deployment file
BRIDGE_DEPLOYMENT_FILE="solidity/tbtc-stub/deployments/development/Bridge.json"
if [ -f "$BRIDGE_DEPLOYMENT_FILE" ]; then
  BRIDGE_ADDRESS=$(jq -r '.address' "$BRIDGE_DEPLOYMENT_FILE" 2>/dev/null || echo "")
fi
BRIDGE="${BRIDGE_ADDRESS:-0xE050D7EA1Bb14278cBFCa591EaA887e48C9BdE08}"

print_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -w, --wallet HASH      Wallet public key hash (20 bytes, 0x prefixed)"
    echo "  -a, --amount SATS      Amount in satoshis to redeem"
    echo "  -s, --script HEX       Bitcoin redeemer output script (hex)"
    echo "  --create-request       Create redemption request first (requires -w, -a, -s)"
    echo "  --monitor-only         Only monitor for proposals (don't create request)"
    echo "  --duration SECONDS     How long to monitor (default: 600)"
    echo "  --list-wallets         List available wallets and exit"
    echo "  -h, --help             Show this help"
    echo ""
    echo "Examples:"
    echo "  # Create request and monitor for proposal"
    echo "  $0 --create-request --wallet 0x... --amount 100000 --script 0x76a914...88ac"
    echo ""
    echo "  # Monitor existing requests for proposal creation"
    echo "  $0 --monitor-only --wallet 0x..."
    echo ""
    echo "  # List available wallets"
    echo "  $0 --list-wallets"
}

# Parse arguments
WALLET_PUBKEY_HASH=""
AMOUNT=""
REDEEMER_SCRIPT=""
CREATE_REQUEST=false
MONITOR_ONLY=false
LIST_WALLETS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -w|--wallet) WALLET_PUBKEY_HASH="$2"; shift 2 ;;
        -a|--amount) AMOUNT="$2"; shift 2 ;;
        -s|--script) REDEEMER_SCRIPT="$2"; shift 2 ;;
        --create-request) CREATE_REQUEST=true; shift ;;
        --monitor-only) MONITOR_ONLY=true; shift ;;
        --duration) MONITOR_DURATION="$2"; shift 2 ;;
        --list-wallets) LIST_WALLETS=true; shift ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo "Unknown option: $1"; print_usage; exit 1 ;;
    esac
done

echo -e "${BLUE}=========================================="
echo "Redemption Proposal Monitor"
echo -e "==========================================${NC}"
echo ""
echo "Bridge: $BRIDGE"
echo "RPC: $RPC_URL"
echo "Coordination frequency: Every $COORDINATION_FREQUENCY blocks"
echo ""

# Function to list wallets
list_wallets() {
    echo -e "${YELLOW}Checking wallets registered in Bridge...${NC}"
    echo ""
    
    KNOWN_HASHES=(
        "0x9850b965a0ef404ce03dd88691201cc537beaefd"
        "0x49be77e65eaa59efe636c5757fd3c31fc5efbb66"
        "0xfed577fbba8e72ec01810e12b09d974d7ef6b6bf"
    )
    
    for HASH in "${KNOWN_HASHES[@]}"; do
        STATE=$(cast call $BRIDGE "wallets(bytes20)" "$HASH" --rpc-url $RPC_URL 2>/dev/null || echo "error")
        
        if [ "$STATE" = "error" ]; then
            echo "  $HASH: ERROR"
        elif [[ "$STATE" =~ ^0x0+$ ]]; then
            echo -e "  $HASH: ${RED}NOT REGISTERED${NC}"
        else
            echo -e "  $HASH: ${GREEN}REGISTERED${NC}"
        fi
    done
    echo ""
}

if [ "$LIST_WALLETS" = true ]; then
    list_wallets
    exit 0
fi

# Create redemption request if requested
if [ "$CREATE_REQUEST" = true ]; then
    if [ -z "$WALLET_PUBKEY_HASH" ] || [ -z "$AMOUNT" ] || [ -z "$REDEEMER_SCRIPT" ]; then
        echo -e "${RED}Error: --create-request requires --wallet, --amount, and --script${NC}"
        exit 1
    fi
    
    echo -e "${CYAN}Creating redemption request...${NC}"
    echo ""
    
    # Use the existing request-redemption script
    if [ -f "scripts/request-redemption.sh" ]; then
        scripts/request-redemption.sh \
            --wallet "$WALLET_PUBKEY_HASH" \
            --amount "$AMOUNT" \
            --script "$REDEEMER_SCRIPT" \
            --unlocked || {
            echo -e "${RED}Failed to create redemption request${NC}"
            exit 1
        }
    else
        echo -e "${YELLOW}Warning: request-redemption.sh not found, skipping request creation${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}Redemption request created. Waiting for coordination window...${NC}"
    echo ""
fi

# Monitor mode requires wallet PKH
if [ "$MONITOR_ONLY" = true ] && [ -z "$WALLET_PUBKEY_HASH" ]; then
    echo -e "${YELLOW}Warning: --monitor-only specified but no wallet PKH. Monitoring all wallets...${NC}"
fi

# Get current block and calculate next coordination window
CURRENT_BLOCK=$(cast block-number --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
CURRENT_WINDOW_INDEX=$((CURRENT_BLOCK / COORDINATION_FREQUENCY))
CURRENT_WINDOW_START=$((CURRENT_WINDOW_INDEX * COORDINATION_FREQUENCY))
NEXT_WINDOW_START=$(((CURRENT_WINDOW_INDEX + 1) * COORDINATION_FREQUENCY))
BLOCKS_REMAINING=$((NEXT_WINDOW_START - CURRENT_BLOCK))

echo -e "${CYAN}Current Status:${NC}"
echo "  Current block: $CURRENT_BLOCK"
echo "  Current window: Block $CURRENT_WINDOW_START (index $CURRENT_WINDOW_INDEX)"
echo "  Next window: Block $NEXT_WINDOW_START (index $((CURRENT_WINDOW_INDEX + 1)))"
echo "  Blocks until next window: $BLOCKS_REMAINING"
echo ""

# Check if we're in a coordination window
BLOCKS_INTO_WINDOW=$((CURRENT_BLOCK - CURRENT_WINDOW_START))
if [ $BLOCKS_INTO_WINDOW -lt 80 ]; then
    echo -e "${GREEN}✓ Currently in ACTIVE PHASE of coordination window${NC}"
    echo "  Active phase ends at block $((CURRENT_WINDOW_START + 80))"
elif [ $BLOCKS_INTO_WINDOW -lt 100 ]; then
    echo -e "${YELLOW}⚠ Currently in PASSIVE PHASE of coordination window${NC}"
    echo "  Window ends at block $((CURRENT_WINDOW_START + 100))"
else
    echo -e "${BLUE}⏳ Between coordination windows${NC}"
    echo "  Next window starts at block $NEXT_WINDOW_START"
fi
echo ""

# Monitor node logs for redemption proposal creation
echo -e "${CYAN}Monitoring node logs for redemption proposal creation...${NC}"
echo "  Duration: $MONITOR_DURATION seconds"
echo "  Log directory: $LOG_DIR"
echo ""

if [ -n "$WALLET_PUBKEY_HASH" ]; then
    WALLET_SHORT=$(echo "$WALLET_PUBKEY_HASH" | cut -c1-10)
    echo "  Filtering for wallet: $WALLET_SHORT..."
fi

echo ""
echo -e "${YELLOW}Looking for redemption proposal logs...${NC}"
echo "  (Searching for: 'preparing a redemption proposal', 'redemption proposal', 'found.*redemption requests')"
echo ""

# Function to check logs
check_logs() {
    local search_pattern="preparing a redemption proposal|redemption proposal|found.*redemption requests|redemption transaction fee"
    
    if [ -n "$WALLET_PUBKEY_HASH" ]; then
        # Search for wallet-specific logs
        WALLET_HEX=$(echo "$WALLET_PUBKEY_HASH" | sed 's/0x//')
        grep -h -i "$search_pattern" "$LOG_DIR"/node*.log 2>/dev/null | \
            grep -i "$WALLET_HEX" | tail -20
    else
        # Search all redemption proposal logs
        grep -h -i "$search_pattern" "$LOG_DIR"/node*.log 2>/dev/null | tail -20
    fi
}

# Initial check
INITIAL_LOGS=$(check_logs)
if [ -n "$INITIAL_LOGS" ]; then
    echo -e "${GREEN}Found existing redemption proposal logs:${NC}"
    echo "$INITIAL_LOGS"
    echo ""
fi

# Monitor for new logs
echo -e "${CYAN}Monitoring for new redemption proposals...${NC}"
echo "  (Press Ctrl+C to stop)"
echo ""

START_TIME=$(date +%s)
LAST_BLOCK=$CURRENT_BLOCK

while true; do
    ELAPSED=$(($(date +%s) - START_TIME))
    
    if [ $ELAPSED -ge $MONITOR_DURATION ]; then
        echo ""
        echo -e "${YELLOW}Monitoring duration reached ($MONITOR_DURATION seconds)${NC}"
        break
    fi
    
    # Check current block
    CURRENT_BLOCK=$(cast block-number --rpc-url "$RPC_URL" 2>/dev/null || echo "$LAST_BLOCK")
    
    # Check if we've entered a new coordination window
    CURRENT_WINDOW_START=$((CURRENT_BLOCK / COORDINATION_FREQUENCY * COORDINATION_FREQUENCY))
    if [ "$CURRENT_BLOCK" != "$LAST_BLOCK" ]; then
        BLOCKS_INTO_WINDOW=$((CURRENT_BLOCK - CURRENT_WINDOW_START))
        
        if [ $BLOCKS_INTO_WINDOW -eq 0 ]; then
            echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${GREEN}🎯 COORDINATION WINDOW STARTED at block $CURRENT_BLOCK${NC}"
            echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
        elif [ $BLOCKS_INTO_WINDOW -eq 80 ]; then
            echo -e "${YELLOW}⚠ Active phase ended at block $CURRENT_BLOCK${NC}"
            echo ""
        fi
        
        LAST_BLOCK=$CURRENT_BLOCK
    fi
    
    # Check for new logs
    NEW_LOGS=$(check_logs | tail -5)
    if [ -n "$NEW_LOGS" ] && [ "$NEW_LOGS" != "$LAST_LOGS" ]; then
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}📋 REDEMPTION PROPOSAL DETECTED!${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo "$NEW_LOGS"
        echo ""
        echo -e "${CYAN}Block: $CURRENT_BLOCK${NC}"
        echo ""
        
        # Show more context
        echo -e "${YELLOW}Recent redemption-related logs:${NC}"
        check_logs | tail -10
        echo ""
        
        LAST_LOGS="$NEW_LOGS"
    fi
    
    # Show status every 30 seconds
    if [ $((ELAPSED % 30)) -eq 0 ] && [ $ELAPSED -gt 0 ]; then
        BLOCKS_REMAINING=$((NEXT_WINDOW_START - CURRENT_BLOCK))
        echo -e "${BLUE}[$ELAPSED/$MONITOR_DURATION] Block $CURRENT_BLOCK | Blocks until next window: $BLOCKS_REMAINING${NC}"
    fi
    
    sleep 2
done

echo ""
echo -e "${CYAN}Final check for redemption proposals...${NC}"
FINAL_LOGS=$(check_logs)
if [ -n "$FINAL_LOGS" ]; then
    echo "$FINAL_LOGS"
else
    echo -e "${YELLOW}No redemption proposals found in logs${NC}"
    echo ""
    echo "This could mean:"
    echo "  1. No pending redemption requests exist"
    echo "  2. Coordination window hasn't occurred yet"
    echo "  3. Wallet is busy with another action"
    echo "  4. Redemption requests don't meet minimum age requirement"
fi

echo ""
echo -e "${BLUE}=========================================="
echo "Monitoring Complete"
echo -e "==========================================${NC}"
echo ""
echo "To check pending redemption requests:"
echo "  cast call $BRIDGE \"getPendingRedemption(uint256)\" <redemptionKey> --rpc-url $RPC_URL"
echo ""
echo "To check next coordination window:"
echo "  scripts/monitor-coordination-window.sh"
