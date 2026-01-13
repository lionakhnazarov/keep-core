#!/bin/bash
# Check DKG approval state and diagnose revert issues

set -e

RPC_URL="${RPC_URL:-http://localhost:8545}"
WALLET_REGISTRY="${WALLET_REGISTRY:-0xd49141e044801DEE237993deDf9684D59fafE2e6}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "=========================================="
echo "DKG Approval State Check"
echo "=========================================="
echo "RPC URL: $RPC_URL"
echo "WalletRegistry: $WALLET_REGISTRY"
echo "=========================================="
echo ""

# Check if cast is available
if ! command -v cast &> /dev/null; then
    echo -e "${RED}Error: 'cast' command not found. Please install foundry.${NC}"
    exit 1
fi

# Get current block
CURRENT_BLOCK=$(cast block-number --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
echo -e "${BLUE}Current Block:${NC} $CURRENT_BLOCK"
echo ""

# Get wallet creation state
echo -e "${BLUE}1. Wallet Creation State:${NC}"
STATE=$(cast call "$WALLET_REGISTRY" "getWalletCreationState()(uint8)" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
if [ -n "$STATE" ]; then
    case "$STATE" in
        0) echo -e "   State: ${GREEN}IDLE${NC} (0)" ;;
        1) echo -e "   State: ${YELLOW}AWAITING_SEED${NC} (1)" ;;
        2) echo -e "   State: ${YELLOW}AWAITING_RESULT${NC} (2)" ;;
        3) echo -e "   State: ${CYAN}CHALLENGE${NC} (3)" ;;
        *) echo -e "   State: ${RED}UNKNOWN ($STATE)${NC}" ;;
    esac
else
    echo -e "${RED}   Could not retrieve state${NC}"
fi
echo ""

# Try to get submitted result block
echo -e "${BLUE}2. Submitted Result Block:${NC}"
SUBMITTED_BLOCK=$(cast call "$WALLET_REGISTRY" "submittedResultBlock()(uint256)" --rpc-url "$RPC_URL" 2>/dev/null || echo "REVERT")
if [ "$SUBMITTED_BLOCK" != "REVERT" ]; then
    echo "   Block: $SUBMITTED_BLOCK"
    if [ "$SUBMITTED_BLOCK" != "0" ]; then
        BLOCKS_SINCE=$((CURRENT_BLOCK - SUBMITTED_BLOCK))
        echo "   Blocks since submission: $BLOCKS_SINCE"
    fi
else
    echo -e "${YELLOW}   Call reverted - no submitted result or wrong state${NC}"
fi
echo ""

# Get DKG parameters
echo -e "${BLUE}3. DKG Parameters:${NC}"
DKG_PARAMS=$(cast call "$WALLET_REGISTRY" "dkgParameters()" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
if [ -n "$DKG_PARAMS" ]; then
    # Parse the hex response
    CHALLENGE_PERIOD=$(echo "$DKG_PARAMS" | cut -c1-66 | xargs -I {} cast --to-dec {} 2>/dev/null || echo "")
    PRECEDENCE_PERIOD=$(echo "$DKG_PARAMS" | cut -c67-130 | xargs -I {} cast --to-dec {} 2>/dev/null || echo "")
    SUBMISSION_TIMEOUT=$(echo "$DKG_PARAMS" | cut -c131-194 | xargs -I {} cast --to-dec {} 2>/dev/null || echo "")
    SEED_TIMEOUT=$(echo "$DKG_PARAMS" | cut -c195-258 | xargs -I {} cast --to-dec {} 2>/dev/null || echo "")
    
    echo "   Challenge Period: ${CHALLENGE_PERIOD:-unknown} blocks"
    echo "   Precedence Period: ${PRECEDENCE_PERIOD:-unknown} blocks"
    echo "   Submission Timeout: ${SUBMISSION_TIMEOUT:-unknown} blocks"
    echo "   Seed Timeout: ${SEED_TIMEOUT:-unknown} blocks"
    
    if [ -n "$SUBMITTED_BLOCK" ] && [ "$SUBMITTED_BLOCK" != "REVERT" ] && [ "$SUBMITTED_BLOCK" != "0" ] && [ -n "$CHALLENGE_PERIOD" ] && [ -n "$PRECEDENCE_PERIOD" ]; then
        CHALLENGE_END=$((SUBMITTED_BLOCK + CHALLENGE_PERIOD))
        PRECEDENCE_START=$((CHALLENGE_END + 1))
        PRECEDENCE_END=$((PRECEDENCE_START + PRECEDENCE_PERIOD))
        GENERAL_START=$((PRECEDENCE_END + 1))
        
        echo ""
        echo -e "${CYAN}   Approval Timeline:${NC}"
        echo "   Submission Block: $SUBMITTED_BLOCK"
        echo "   Challenge Period End: $CHALLENGE_END"
        echo "   Precedence Period Start: $PRECEDENCE_START"
        echo "   Precedence Period End: $PRECEDENCE_END"
        echo "   General Approval Start: $GENERAL_START"
        echo ""
        
        if [ "$CURRENT_BLOCK" -lt "$PRECEDENCE_START" ]; then
            echo -e "${RED}   ❌ Current block ($CURRENT_BLOCK) is BEFORE precedence period${NC}"
            echo "   Need $((PRECEDENCE_START - CURRENT_BLOCK)) more blocks"
        elif [ "$CURRENT_BLOCK" -ge "$PRECEDENCE_START" ] && [ "$CURRENT_BLOCK" -lt "$GENERAL_START" ]; then
            echo -e "${YELLOW}   ⚠️  Current block ($CURRENT_BLOCK) is in PRECEDENCE period${NC}"
            echo "   Only submitter can approve until block $GENERAL_START"
        else
            echo -e "${GREEN}   ✅ Current block ($CURRENT_BLOCK) is in GENERAL approval period${NC}"
            echo "   Anyone can approve"
        fi
    fi
else
    echo -e "${RED}   Could not retrieve DKG parameters${NC}"
fi
echo ""

# Check for recent DKG events
echo -e "${BLUE}4. Recent DKG Events:${NC}"
echo "   Checking for DkgResultSubmitted events..."
SUBMITTED_EVENTS=$(cast logs --from-block $((CURRENT_BLOCK - 1000)) --to-block latest \
    "DkgResultSubmitted(bytes32 indexed,uint256 indexed,(uint256,bytes,uint8[],bytes,uint256[],uint32[],bytes32))" \
    --address "$WALLET_REGISTRY" --rpc-url "$RPC_URL" 2>/dev/null | head -5 || echo "")
if [ -n "$SUBMITTED_EVENTS" ]; then
    echo "$SUBMITTED_EVENTS"
else
    echo -e "${YELLOW}   No recent submission events found${NC}"
fi

echo ""
echo "   Checking for DkgResultApproved events..."
APPROVED_EVENTS=$(cast logs --from-block $((CURRENT_BLOCK - 1000)) --to-block latest \
    "DkgResultApproved(bytes32 indexed,address indexed)" \
    --address "$WALLET_REGISTRY" --rpc-url "$RPC_URL" 2>/dev/null | head -5 || echo "")
if [ -n "$APPROVED_EVENTS" ]; then
    echo -e "${GREEN}$APPROVED_EVENTS${NC}"
else
    echo -e "${YELLOW}   No recent approval events found${NC}"
fi

echo ""
echo "   Checking for DkgResultChallenged events..."
CHALLENGED_EVENTS=$(cast logs --from-block $((CURRENT_BLOCK - 1000)) --to-block latest \
    "DkgResultChallenged(bytes32 indexed,address indexed,string)" \
    --address "$WALLET_REGISTRY" --rpc-url "$RPC_URL" 2>/dev/null | head -5 || echo "")
if [ -n "$CHALLENGED_EVENTS" ]; then
    echo -e "${RED}$CHALLENGED_EVENTS${NC}"
else
    echo -e "${GREEN}   No recent challenge events found${NC}"
fi
echo ""

# Summary
echo -e "${BLUE}=== Summary ===${NC}"
if [ "$STATE" = "3" ]; then
    echo -e "${CYAN}✓ State is CHALLENGE - ready for approval${NC}"
    if [ "$SUBMITTED_BLOCK" != "REVERT" ] && [ "$SUBMITTED_BLOCK" != "0" ]; then
        if [ -n "$CHALLENGE_PERIOD" ] && [ -n "$PRECEDENCE_PERIOD" ]; then
            CHALLENGE_END=$((SUBMITTED_BLOCK + CHALLENGE_PERIOD))
            PRECEDENCE_START=$((CHALLENGE_END + 1))
            GENERAL_START=$((PRECEDENCE_START + PRECEDENCE_PERIOD + 1))
            
            if [ "$CURRENT_BLOCK" -lt "$PRECEDENCE_START" ]; then
                echo -e "${RED}✗ Too early - need block $PRECEDENCE_START${NC}"
            elif [ "$CURRENT_BLOCK" -ge "$PRECEDENCE_START" ] && [ "$CURRENT_BLOCK" -lt "$GENERAL_START" ]; then
                echo -e "${YELLOW}⚠ Only submitter can approve until block $GENERAL_START${NC}"
            else
                echo -e "${GREEN}✓ Timing is correct for approval${NC}"
                echo -e "${YELLOW}If approval still fails, likely causes:${NC}"
                echo "  1. Result hash mismatch"
                echo "  2. Member not eligible (disqualified/inactive)"
                echo "  3. Result was challenged"
            fi
        fi
    else
        echo -e "${RED}✗ No submitted result found - state may have changed${NC}"
    fi
else
    echo -e "${YELLOW}State is not CHALLENGE - cannot approve${NC}"
fi


