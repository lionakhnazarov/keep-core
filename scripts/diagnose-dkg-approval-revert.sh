#!/bin/bash
# Diagnostic script for DKG approval revert issues
# Usage: ./scripts/diagnose-dkg-approval-revert.sh [resultHash] [submissionBlock]

set -e

RPC_URL="${RPC_URL:-http://localhost:8545}"
RESULT_HASH="${1:-0x4020d2456623b188c9f5a0692e0938fbf59658b8f7f89a1b743db7c416ff822e}"
SUBMISSION_BLOCK="${2:-862}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "DKG Approval Revert Diagnostic"
echo "=========================================="
echo "RPC URL: $RPC_URL"
echo "Result Hash: $RESULT_HASH"
echo "Submission Block: $SUBMISSION_BLOCK"
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

# Try to get WalletRegistry address from Bridge
echo -e "${BLUE}1. Checking WalletRegistry contract...${NC}"
BRIDGE_ADDRESS=$(grep -A 10 "\[ethereum\]" config.toml 2>/dev/null | grep -i "Bridge" | head -1 | cut -d'=' -f2 | tr -d ' "' || echo "")

if [ -z "$BRIDGE_ADDRESS" ]; then
    echo -e "${YELLOW}Warning: Could not find Bridge address in config.toml${NC}"
    echo "Please provide WalletRegistry address manually:"
    read -r WALLET_REGISTRY_ADDRESS
else
    echo "Bridge address: $BRIDGE_ADDRESS"
    WALLET_REGISTRY_ADDRESS=$(cast call "$BRIDGE_ADDRESS" "ecdsaWalletRegistry()" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
    if [ -z "$WALLET_REGISTRY_ADDRESS" ]; then
        echo -e "${YELLOW}Could not get WalletRegistry from Bridge${NC}"
        echo "Please provide WalletRegistry address manually:"
        read -r WALLET_REGISTRY_ADDRESS
    else
        echo "WalletRegistry address: $WALLET_REGISTRY_ADDRESS"
    fi
fi

if [ -z "$WALLET_REGISTRY_ADDRESS" ]; then
    echo -e "${RED}Error: WalletRegistry address is required${NC}"
    exit 1
fi

echo ""

# Get DKG parameters
echo -e "${BLUE}2. Checking DKG Parameters...${NC}"
DKG_PARAMS=$(cast call "$WALLET_REGISTRY_ADDRESS" "dkgParameters()" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
if [ -n "$DKG_PARAMS" ]; then
    echo "DKG Parameters: $DKG_PARAMS"
    # Parse parameters (format may vary)
    CHALLENGE_PERIOD=$(echo "$DKG_PARAMS" | grep -o "challengePeriodLength: [0-9]*" | awk '{print $2}' || echo "")
    PRECEDENCE_PERIOD=$(echo "$DKG_PARAMS" | grep -o "submitterPrecedencePeriodLength: [0-9]*" | awk '{print $2}' || echo "")
    echo "Challenge Period: ${CHALLENGE_PERIOD:-unknown} blocks"
    echo "Precedence Period: ${PRECEDENCE_PERIOD:-unknown} blocks"
else
    echo -e "${YELLOW}Could not retrieve DKG parameters${NC}"
fi

echo ""

# Calculate expected approval blocks
if [ -n "$CHALLENGE_PERIOD" ] && [ -n "$PRECEDENCE_PERIOD" ]; then
    echo -e "${BLUE}3. Calculating Approval Windows...${NC}"
    CHALLENGE_END=$((SUBMISSION_BLOCK + CHALLENGE_PERIOD))
    PRECEDENCE_START=$((CHALLENGE_END + 1))
    PRECEDENCE_END=$((PRECEDENCE_START + PRECEDENCE_PERIOD))
    GENERAL_START=$((PRECEDENCE_END + 1))
    
    echo "Submission Block: $SUBMISSION_BLOCK"
    echo "Challenge Period End: $CHALLENGE_END"
    echo "Precedence Period Start: $PRECEDENCE_START"
    echo "Precedence Period End: $PRECEDENCE_END"
    echo "General Approval Start: $GENERAL_START"
    echo ""
    
    if [ "$CURRENT_BLOCK" -lt "$PRECEDENCE_START" ]; then
        echo -e "${YELLOW}Current block ($CURRENT_BLOCK) is before precedence period start ($PRECEDENCE_START)${NC}"
        echo "Submitter cannot approve yet. Need $((PRECEDENCE_START - CURRENT_BLOCK)) more blocks."
    elif [ "$CURRENT_BLOCK" -lt "$GENERAL_START" ]; then
        echo -e "${GREEN}Current block ($CURRENT_BLOCK) is in precedence period${NC}"
        echo "Only submitter can approve at this time."
    else
        echo -e "${GREEN}Current block ($CURRENT_BLOCK) is in general approval period${NC}"
        echo "All members can approve."
    fi
fi

echo ""

# Check if result was already approved
echo -e "${BLUE}4. Checking if Result Already Approved...${NC}"
# Try to get approval count or status
APPROVAL_COUNT=$(cast call "$WALLET_REGISTRY_ADDRESS" "getDkgResultApprovalCount(bytes32)(uint256)" "$RESULT_HASH" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
if [ -n "$APPROVAL_COUNT" ]; then
    echo "Approval Count: $APPROVAL_COUNT"
    if [ "$APPROVAL_COUNT" != "0" ]; then
        echo -e "${GREEN}Result has been approved $APPROVAL_COUNT time(s)${NC}"
    fi
else
    echo -e "${YELLOW}Could not check approval count (method may not exist)${NC}"
fi

echo ""

# Check wallet creation state
echo -e "${BLUE}5. Checking Wallet Creation State...${NC}"
WALLET_STATE=$(cast call "$WALLET_REGISTRY_ADDRESS" "getWalletCreationState()(uint8)" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
if [ -n "$WALLET_STATE" ]; then
    case "$WALLET_STATE" in
        0) echo "State: IDLE" ;;
        1) echo "State: AWAITING_SEED" ;;
        2) echo "State: AWAITING_RESULT" ;;
        3) echo "State: CHALLENGE" ;;
        4) echo "State: AWAITING_APPROVAL" ;;
        5) echo "State: APPROVED" ;;
        *) echo "State: UNKNOWN ($WALLET_STATE)" ;;
    esac
else
    echo -e "${YELLOW}Could not retrieve wallet creation state${NC}"
fi

echo ""

# Check submitted result block
echo -e "${BLUE}6. Checking Submitted Result Block...${NC}"
SUBMITTED_BLOCK=$(cast call "$WALLET_REGISTRY_ADDRESS" "submittedResultBlock()(uint256)" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
if [ -n "$SUBMITTED_BLOCK" ]; then
    echo "Submitted Result Block: $SUBMITTED_BLOCK"
    if [ "$SUBMITTED_BLOCK" != "$SUBMISSION_BLOCK" ]; then
        echo -e "${YELLOW}Warning: Submitted block mismatch! Expected $SUBMISSION_BLOCK, got $SUBMITTED_BLOCK${NC}"
    fi
else
    echo -e "${YELLOW}Could not retrieve submitted result block${NC}"
fi

echo ""

# Summary
echo -e "${BLUE}=== Summary ===${NC}"
echo "Current Block: $CURRENT_BLOCK"
if [ -n "$PRECEDENCE_START" ]; then
    if [ "$CURRENT_BLOCK" -lt "$PRECEDENCE_START" ]; then
        echo -e "${RED}Issue: Current block is too early for approval${NC}"
        echo "  - Need to wait for block $PRECEDENCE_START"
        echo "  - $((PRECEDENCE_START - CURRENT_BLOCK)) blocks remaining"
    elif [ "$CURRENT_BLOCK" -ge "$PRECEDENCE_START" ] && [ "$CURRENT_BLOCK" -lt "$GENERAL_START" ]; then
        echo -e "${YELLOW}Note: In precedence period - only submitter can approve${NC}"
    else
        echo -e "${GREEN}Block timing looks correct for approval${NC}"
    fi
fi

if [ -n "$APPROVAL_COUNT" ] && [ "$APPROVAL_COUNT" != "0" ]; then
    echo -e "${GREEN}Result has already been approved${NC}"
fi

echo ""
echo "To manually approve, use:"
echo "  cast send $WALLET_REGISTRY_ADDRESS \"approveDkgResult(...)\" --rpc-url $RPC_URL --unlocked"


