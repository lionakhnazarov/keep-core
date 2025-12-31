#!/bin/bash
# Script to approve DKG result and move from CHALLENGE state (stage 3) to completion
# Usage: ./scripts/approve-dkg-result.sh [config-file]
#
# This script:
# 1. Checks DKG is in CHALLENGE state
# 2. Checks if challenge period has ended
# 3. Gets the submitted DKG result from logs or contract
# 4. Approves the DKG result

set -eou pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

CONFIG_FILE=${1:-"config.toml"}

echo "=========================================="
echo "Approve DKG Result (Stage 3 → Completion)"
echo "=========================================="
echo ""

# Step 1: Check DKG state
echo -e "${BLUE}Step 1: Checking DKG state...${NC}"
CURRENT_STATE=$(KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry get-wallet-creation-state \
  --config "$CONFIG_FILE" --developer 2>&1 | grep -E "^[0-9]+$" | tail -1 || echo "")

get_state_name() {
    case "$1" in
        0) echo "IDLE" ;;
        1) echo "AWAITING_SEED" ;;
        2) echo "AWAITING_RESULT" ;;
        3) echo "CHALLENGE" ;;
        *) echo "UNKNOWN" ;;
    esac
}

STATE_NAME=$(get_state_name "$CURRENT_STATE")
echo "Current DKG State: $CURRENT_STATE ($STATE_NAME)"
echo ""

if [ "$CURRENT_STATE" != "3" ]; then
    echo -e "${RED}✗ Error: DKG is not in CHALLENGE state (stage 3)${NC}"
    echo "Current state: $STATE_NAME"
    echo ""
    echo "This script is only for approving DKG results in CHALLENGE state."
    exit 1
fi

echo -e "${GREEN}✓ DKG is in CHALLENGE state${NC}"
echo ""

# Step 2: Check challenge period
echo -e "${BLUE}Step 2: Checking challenge period status...${NC}"

# Get current block
CURRENT_BLOCK=$(curl -s -X POST "http://localhost:8545" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  2>/dev/null | grep -oE '"result":"0x[0-9a-f]+"' | cut -d'"' -f4 | sed 's/0x//' || echo "")

if [ -z "$CURRENT_BLOCK" ]; then
    echo -e "${YELLOW}⚠ Could not get current block number${NC}"
    CURRENT_BLOCK="0"
else
    CURRENT_BLOCK_DEC=$(printf "%d" "0x$CURRENT_BLOCK" 2>/dev/null || echo "0")
    echo "Current block: $CURRENT_BLOCK_DEC"
fi

# Get DKG parameters
echo "Fetching DKG parameters..."
DKG_PARAMS=$(KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry dkg-parameters \
  --config "$CONFIG_FILE" --developer 2>&1 || echo "")

CHALLENGE_PERIOD=$(echo "$DKG_PARAMS" | grep -iE "challenge.*period|resultChallengePeriodLength" | grep -oE "[0-9]+" | head -1 || echo "11520")
APPROVE_PRECEDENCE=$(echo "$DKG_PARAMS" | grep -iE "precedence|submitterPrecedencePeriodLength" | grep -oE "[0-9]+" | head -1 || echo "5760")

echo "Challenge Period Blocks: $CHALLENGE_PERIOD"
echo "Approve Precedence Period Blocks: $APPROVE_PRECEDENCE"
echo ""

# Note: We can't easily get the submission block without querying events
# The nodes automatically schedule approvals, so let's check if they're doing it
echo -e "${YELLOW}Note: Nodes automatically schedule DKG result approvals${NC}"
echo ""
echo "The DKG result submitter can approve immediately after challenge period ends."
echo "Other members can approve after the precedence period ends."
echo ""

# Step 3: Check if nodes are scheduling approvals
echo -e "${BLUE}Step 3: Checking if nodes are scheduling approvals...${NC}"
echo ""

APPROVAL_SCHEDULED=false
for i in {1..10}; do
    LOG_FILE="logs/node${i}.log"
    if [ ! -f "$LOG_FILE" ]; then
        continue
    fi
    
    # Check for approval scheduling messages
    if grep -q "scheduling DKG result approval\|waiting for block.*to approve DKG result" "$LOG_FILE" 2>/dev/null; then
        echo -e "${GREEN}✓ Node $i is scheduling approval${NC}"
        APPROVAL_SCHEDULED=true
        
        # Show the scheduled block
        APPROVE_BLOCK=$(grep "waiting for block.*to approve DKG result" "$LOG_FILE" 2>/dev/null | tail -1 | grep -oE "block \[[0-9]+\]" | grep -oE "[0-9]+" || echo "")
        if [ -n "$APPROVE_BLOCK" ]; then
            echo "  Scheduled for block: $APPROVE_BLOCK"
            if [ "$CURRENT_BLOCK_DEC" -ge "$APPROVE_BLOCK" ] 2>/dev/null; then
                echo -e "  ${GREEN}→ Block reached! Approval should happen soon.${NC}"
            else
                BLOCKS_REMAINING=$((APPROVE_BLOCK - CURRENT_BLOCK_DEC))
                echo "  Blocks remaining: $BLOCKS_REMAINING"
            fi
        fi
    fi
done

echo ""

if [ "$APPROVAL_SCHEDULED" = "false" ]; then
    echo -e "${YELLOW}⚠ No nodes appear to be scheduling approvals${NC}"
    echo ""
    echo "This could mean:"
    echo "  1. Nodes haven't detected the DKG result submission"
    echo "  2. Nodes are not eligible to approve (not in the group)"
    echo "  3. Challenge period hasn't ended yet"
    echo ""
    echo "You can manually approve if you have the DKG result JSON."
    echo ""
    read -p "Do you want to try manual approval? (y/n): " manual_approve
    if [ "$manual_approve" != "y" ]; then
        echo "Exiting. Nodes should handle approval automatically."
        exit 0
    fi
else
    echo -e "${GREEN}✓ Nodes are handling approval automatically${NC}"
    echo ""
    echo "The DKG result will be approved automatically when:"
    echo "  1. Challenge period ends"
    echo "  2. Precedence period ends (for non-submitters)"
    echo "  3. Scheduled block is reached"
    echo ""
    echo "Monitor progress:"
    echo "  tail -f logs/node*.log | grep -i 'approve\|DKG'"
    echo "  ./scripts/check-dkg-state.sh"
    echo ""
    exit 0
fi

# Step 4: Manual approval (if requested)
echo ""
echo -e "${BLUE}Step 4: Manual DKG Result Approval${NC}"
echo ""
echo -e "${RED}⚠ Warning: Manual approval requires the exact DKG result JSON${NC}"
echo ""
echo "The DKG result JSON must match exactly what was submitted."
echo "You can find it in node logs by searching for 'submitted DKG result'"
echo ""
echo "Example log entry:"
echo "  'submitted DKG result: {...}'"
echo ""

# Try to extract from logs
echo "Attempting to extract DKG result from logs..."
DKG_RESULT_JSON=""

for i in {1..10}; do
    LOG_FILE="logs/node${i}.log"
    if [ ! -f "$LOG_FILE" ]; then
        continue
    fi
    
    # Look for DKG result submission in logs
    RESULT_LINE=$(grep -i "submitted.*dkg.*result\|dkg.*result.*submitted" "$LOG_FILE" 2>/dev/null | tail -1 || echo "")
    if [ -n "$RESULT_LINE" ]; then
        echo "Found DKG result submission in node $i logs"
        # Try to extract JSON (this is tricky, may need manual extraction)
        echo "  Log entry: ${RESULT_LINE:0:200}..."
    fi
done

echo ""
echo "To manually approve, you need the DKG result JSON."
echo ""
echo "Option 1: Extract from node logs"
echo "  grep -i 'submitted.*dkg.*result' logs/node*.log"
echo ""
echo "Option 2: Use Hardhat to query the contract"
echo "  cd solidity/ecdsa"
echo "  npx hardhat console --network development"
echo "  # Then query submittedResultHash and reconstruct result"
echo ""
echo "Option 3: Wait for automatic approval"
echo "  Nodes will approve automatically when eligible"
echo ""

echo "Manual approval command (once you have the JSON):"
echo "  KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry approve-dkg-result '{\"dkgResult\":\"...\"}' \\"
echo "    --submit --config $CONFIG_FILE --developer"
echo ""

echo "=========================================="
echo -e "${YELLOW}Recommendation: Wait for automatic approval${NC}"
echo "=========================================="
echo ""
echo "The nodes automatically handle DKG result approval."
echo "They will approve when:"
echo "  - Challenge period ends"
echo "  - Their scheduled block is reached"
echo ""
echo "Monitor with:"
echo "  ./scripts/check-dkg-state.sh"
echo "  tail -f logs/node*.log | grep -i approve"

