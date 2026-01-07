#!/bin/bash
# Comprehensive contract state investigation for DKG approval revert

set -e

RPC_URL="${RPC_URL:-http://localhost:8545}"
WALLET_REGISTRY="${WALLET_REGISTRY:-0xd49141e044801DEE237993deDf9684D59fafE2e6}"
SUBMISSION_BLOCK="${1:-862}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "=========================================="
echo "Comprehensive Contract State Investigation"
echo "=========================================="
echo "RPC URL: $RPC_URL"
echo "WalletRegistry: $WALLET_REGISTRY"
echo "Submission Block: $SUBMISSION_BLOCK"
echo "=========================================="
echo ""

# Check if cast is available
if ! command -v cast &> /dev/null; then
    echo -e "${RED}Error: 'cast' command not found. Please install foundry.${NC}"
    exit 1
fi

CURRENT_BLOCK=$(cast block-number --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
echo -e "${BLUE}Current Block:${NC} $CURRENT_BLOCK"
echo ""

# 1. Check WalletRegistry state
echo -e "${BLUE}=== 1. WalletRegistry State ===${NC}"
STATE=$(cast call "$WALLET_REGISTRY" "getWalletCreationState()(uint8)" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
if [ -n "$STATE" ]; then
    case "$STATE" in
        0) echo -e "State: ${GREEN}IDLE${NC} (0)" ;;
        1) echo -e "State: ${YELLOW}AWAITING_SEED${NC} (1)" ;;
        2) echo -e "State: ${YELLOW}AWAITING_RESULT${NC} (2)" ;;
        3) echo -e "State: ${CYAN}CHALLENGE${NC} (3)" ;;
        *) echo -e "State: ${RED}UNKNOWN ($STATE)${NC}" ;;
    esac
fi
echo ""

# 2. Check SortitionPool state
echo -e "${BLUE}=== 2. SortitionPool State ===${NC}"
# Get SortitionPool address from WalletRegistry
SORTITION_POOL=$(cast call "$WALLET_REGISTRY" "sortitionPool()(address)" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
if [ -n "$SORTITION_POOL" ] && [ "$SORTITION_POOL" != "0x0000000000000000000000000000000000000000" ]; then
    echo "SortitionPool: $SORTITION_POOL"
    IS_LOCKED=$(cast call "$SORTITION_POOL" "isLocked()(bool)" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
    if [ "$IS_LOCKED" = "true" ]; then
        echo -e "Locked: ${GREEN}YES${NC}"
    else
        echo -e "Locked: ${RED}NO${NC}"
        echo -e "${YELLOW}⚠️  SortitionPool should be locked in CHALLENGE state${NC}"
    fi
else
    echo -e "${YELLOW}Could not get SortitionPool address${NC}"
fi
echo ""

# 3. Check for challenge events
echo -e "${BLUE}=== 3. Challenge Events ===${NC}"
CHALLENGE_EVENTS=$(cast logs --from-block $((SUBMISSION_BLOCK - 100)) --to-block latest \
    "DkgResultChallenged(bytes32 indexed,address indexed,string)" \
    --address "$WALLET_REGISTRY" --rpc-url "$RPC_URL" 2>/dev/null | grep -c "DkgResultChallenged" || echo "0")
if [ "$CHALLENGE_EVENTS" != "0" ]; then
    echo -e "${RED}Found $CHALLENGE_EVENTS challenge event(s)${NC}"
    echo "This would reset the state to AWAITING_RESULT"
    cast logs --from-block $((SUBMISSION_BLOCK - 100)) --to-block latest \
        "DkgResultChallenged(bytes32 indexed,address indexed,string)" \
        --address "$WALLET_REGISTRY" --rpc-url "$RPC_URL" 2>/dev/null | head -20
else
    echo -e "${GREEN}No challenge events found${NC}"
fi
echo ""

# 4. Check for approval events
echo -e "${BLUE}=== 4. Approval Events ===${NC}"
APPROVAL_EVENTS=$(cast logs --from-block $((SUBMISSION_BLOCK - 100)) --to-block latest \
    "DkgResultApproved(bytes32 indexed,address indexed)" \
    --address "$WALLET_REGISTRY" --rpc-url "$RPC_URL" 2>/dev/null | grep -c "DkgResultApproved" || echo "0")
if [ "$APPROVAL_EVENTS" != "0" ]; then
    echo -e "${GREEN}Found $APPROVAL_EVENTS approval event(s)${NC}"
    cast logs --from-block $((SUBMISSION_BLOCK - 100)) --to-block latest \
        "DkgResultApproved(bytes32 indexed,address indexed)" \
        --address "$WALLET_REGISTRY" --rpc-url "$RPC_URL" 2>/dev/null | head -10
else
    echo -e "${YELLOW}No approval events found${NC}"
fi
echo ""

# 5. Check DKG parameters
echo -e "${BLUE}=== 5. DKG Parameters ===${NC}"
DKG_PARAMS=$(cast call "$WALLET_REGISTRY" "dkgParameters()" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
if [ -n "$DKG_PARAMS" ]; then
    CHALLENGE_PERIOD=$(echo "$DKG_PARAMS" | cut -c1-66 | xargs -I {} cast --to-dec {} 2>/dev/null || echo "")
    PRECEDENCE_PERIOD=$(echo "$DKG_PARAMS" | cut -c67-130 | xargs -I {} cast --to-dec {} 2>/dev/null || echo "")
    echo "Challenge Period: ${CHALLENGE_PERIOD:-unknown} blocks"
    echo "Precedence Period: ${PRECEDENCE_PERIOD:-unknown} blocks"
fi
echo ""

# 6. Try to get internal DKG state using storage slots
echo -e "${BLUE}=== 6. Internal DKG State (Storage Slots) ===${NC}"
echo "Attempting to read internal state..."
echo ""

# Get the event to find the result hash
EVENT_DATA=$(cast logs --from-block $SUBMISSION_BLOCK --to-block $SUBMISSION_BLOCK \
    "DkgResultSubmitted(bytes32 indexed,uint256 indexed,(uint256,bytes,uint8[],bytes,uint256[],uint32[],bytes32))" \
    --address "$WALLET_REGISTRY" --rpc-url "$RPC_URL" 2>/dev/null | head -1 || echo "")

if [ -n "$EVENT_DATA" ]; then
    RESULT_HASH=$(echo "$EVENT_DATA" | grep -o "0x[a-f0-9]\{64\}" | head -2 | tail -1)
    echo "Result Hash from event: $RESULT_HASH"
    echo ""
    
    # Try to check if this hash is stored in the contract
    echo "Checking if result hash is stored in contract..."
    # We can't directly read it, but we can try to verify by attempting approval
fi

# 7. Check for timeout events
echo -e "${BLUE}=== 7. Timeout Events ===${NC}"
TIMEOUT_EVENTS=$(cast logs --from-block $((SUBMISSION_BLOCK - 100)) --to-block latest \
    "DkgTimedOut()" \
    --address "$WALLET_REGISTRY" --rpc-url "$RPC_URL" 2>/dev/null | grep -c "DkgTimedOut" || echo "0")
if [ "$TIMEOUT_EVENTS" != "0" ]; then
    echo -e "${RED}Found $TIMEOUT_EVENTS timeout event(s)${NC}"
    echo "This would reset the state to IDLE"
else
    echo -e "${GREEN}No timeout events found${NC}"
fi
echo ""

# 8. Check WalletOwner callback
echo -e "${BLUE}=== 8. WalletOwner State ===${NC}"
WALLET_OWNER=$(cast call "$WALLET_REGISTRY" "walletOwner()(address)" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
if [ -n "$WALLET_OWNER" ]; then
    echo "WalletOwner: $WALLET_OWNER"
    # Check if WalletOwner has code (is a contract)
    OWNER_CODE=$(cast code "$WALLET_OWNER" --rpc-url "$RPC_URL" 2>/dev/null | head -c 20 || echo "")
    if [ -n "$OWNER_CODE" ] && [ "$OWNER_CODE" != "0x" ]; then
        echo -e "WalletOwner is a contract: ${GREEN}YES${NC}"
    else
        echo -e "WalletOwner is a contract: ${RED}NO${NC}"
        echo -e "${YELLOW}⚠️  WalletOwner callback might fail${NC}"
    fi
else
    echo -e "${YELLOW}Could not get WalletOwner address${NC}"
fi
echo ""

# 9. Summary and diagnosis
echo -e "${BLUE}=== Summary ===${NC}"
echo ""

if [ "$STATE" = "3" ]; then
    echo -e "${CYAN}✓ State is CHALLENGE${NC}"
    
    if [ "$IS_LOCKED" != "true" ]; then
        echo -e "${RED}✗ SortitionPool is NOT locked (should be locked in CHALLENGE state)${NC}"
        echo -e "${RED}   This is a STATE INCONSISTENCY!${NC}"
    else
        echo -e "${GREEN}✓ SortitionPool is locked${NC}"
    fi
    
    if [ "$CHALLENGE_EVENTS" != "0" ]; then
        echo -e "${RED}✗ Challenge events found - state should be AWAITING_RESULT, not CHALLENGE${NC}"
        echo -e "${RED}   This is a STATE INCONSISTENCY!${NC}"
    fi
    
    if [ "$APPROVAL_EVENTS" != "0" ]; then
        echo -e "${GREEN}✓ Approval events found - result was already approved${NC}"
    fi
    
    if [ "$TIMEOUT_EVENTS" != "0" ]; then
        echo -e "${RED}✗ Timeout events found - state should be IDLE, not CHALLENGE${NC}"
        echo -e "${RED}   This is a STATE INCONSISTENCY!${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}Possible causes of empty revert (0x):${NC}"
    echo "  1. State inconsistency (SortitionPool unlocked but state is CHALLENGE)"
    echo "  2. Internal library state mismatch"
    echo "  3. WalletOwner callback would revert"
    echo "  4. Storage slot corruption"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "  1. Use debug_traceCall to find exact revert point"
    echo "  2. Check storage slots directly"
    echo "  3. Verify WalletOwner contract state"
    echo "  4. Check if a new DKG has started (would explain state reset)"
else
    echo -e "${YELLOW}State is not CHALLENGE - cannot approve${NC}"
fi

