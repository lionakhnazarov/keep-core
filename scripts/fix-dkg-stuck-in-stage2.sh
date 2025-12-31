#!/bin/bash
# Script to fix DKG stuck in AWAITING_RESULT (stage 2)
# This handles timeout scenarios and provides solutions

set -eou pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

CONFIG_FILE="${1:-configs/config.toml}"
RPC_URL="http://localhost:8545"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "Fix DKG Stuck in Stage 2 (AWAITING_RESULT)"
echo "=========================================="
echo ""

# Step 1: Check current state
echo -e "${BLUE}Step 1: Checking DKG state...${NC}"
STATE=$(KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry get-wallet-creation-state \
  --config "$CONFIG_FILE" --developer 2>&1 | grep -E "^[0-9]+$" | head -1 || echo "")

if [ -z "$STATE" ]; then
    echo -e "${RED}✗ Could not get DKG state${NC}"
    exit 1
fi

get_state_name() {
    case "$1" in
        0) echo "IDLE" ;;
        1) echo "AWAITING_SEED" ;;
        2) echo "AWAITING_RESULT" ;;
        3) echo "CHALLENGE" ;;
        *) echo "UNKNOWN" ;;
    esac
}

STATE_NAME=$(get_state_name "$STATE")
echo "Current DKG State: $STATE ($STATE_NAME)"
echo ""

if [ "$STATE" != "2" ]; then
    echo -e "${YELLOW}⚠ DKG is not in AWAITING_RESULT state (state 2)${NC}"
    echo "Current state: $STATE_NAME"
    echo ""
    echo "This script is specifically for fixing DKG stuck in AWAITING_RESULT."
    exit 0
fi

echo -e "${GREEN}✓ DKG is in AWAITING_RESULT state${NC}"
echo ""

# Step 2: Check timeout status
echo -e "${BLUE}Step 2: Checking timeout status...${NC}"
TIMED_OUT=$(KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry has-dkg-timed-out \
  --config "$CONFIG_FILE" --developer 2>&1 | grep -iE "true|false" | head -1 || echo "false")

echo "DKG Timed Out: $TIMED_OUT"
echo ""

# Step 3: Get DKG parameters
echo -e "${BLUE}Step 3: Checking DKG parameters...${NC}"
DKG_PARAMS=$(KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry dkg-parameters \
  --config "$CONFIG_FILE" --developer 2>&1 || echo "")

SUBMISSION_TIMEOUT=$(echo "$DKG_PARAMS" | grep -iE "submission.*timeout|resultSubmissionTimeout" | grep -oE "[0-9]+" | head -1 || echo "30")
echo "Result Submission Timeout: $SUBMISSION_TIMEOUT blocks"
echo ""

# Step 4: Check current block and DKG start block
echo -e "${BLUE}Step 4: Checking block information...${NC}"
CURRENT_BLOCK=$(cast block-number --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
echo "Current Block: $CURRENT_BLOCK"

# Get DKG start block from events
WR=$(jq -r '.address' solidity/ecdsa/deployments/development/WalletRegistry.json 2>/dev/null || echo "")
if [ -n "$WR" ]; then
    # Try to get start block from recent DkgStarted events
    START_BLOCK=$(cast logs --from-block latest-200 --to-block latest \
      --address "$WR" \
      --topic "0x$(cast keccak 'DkgStarted(uint256)' | cut -c1-66)" \
      --rpc-url "$RPC_URL" 2>/dev/null | tail -1 | grep -oE "blockNumber.*[0-9]+" | grep -oE "[0-9]+" || echo "")
    
    if [ -n "$START_BLOCK" ]; then
        echo "DKG Start Block: $START_BLOCK"
        BLOCKS_ELAPSED=$((CURRENT_BLOCK - START_BLOCK))
        echo "Blocks Elapsed: $BLOCKS_ELAPSED"
        echo "Timeout Blocks: $SUBMISSION_TIMEOUT"
        
        if [ "$BLOCKS_ELAPSED" -gt "$SUBMISSION_TIMEOUT" ]; then
            echo -e "${YELLOW}⚠ DKG has exceeded timeout period${NC}"
        fi
    fi
fi
echo ""

# Step 5: Check node logs for protocol progress
echo -e "${BLUE}Step 5: Checking protocol progress in logs...${NC}"
PROTOCOL_STARTED=false
PROTOCOL_COMPLETED=false
RESULT_SUBMITTED=false

for i in {1..10}; do
    LOG_FILE="logs/node${i}.log"
    if [ ! -f "$LOG_FILE" ]; then
        continue
    fi
    
    if grep -q "starting announcement phase\|starting.*phase" "$LOG_FILE" 2>/dev/null; then
        PROTOCOL_STARTED=true
    fi
    
    if grep -q "submitting DKG result\|DKG result.*submitted" "$LOG_FILE" 2>/dev/null; then
        RESULT_SUBMITTED=true
    fi
    
    if grep -q "DKG protocol.*complete\|protocol.*completed" "$LOG_FILE" 2>/dev/null; then
        PROTOCOL_COMPLETED=true
    fi
done

if [ "$PROTOCOL_STARTED" = "true" ]; then
    echo -e "${GREEN}✓ Protocol started${NC}"
else
    echo -e "${YELLOW}⚠ Protocol may not have started${NC}"
fi

if [ "$PROTOCOL_COMPLETED" = "true" ]; then
    echo -e "${GREEN}✓ Protocol completed${NC}"
else
    echo -e "${YELLOW}⚠ Protocol may not have completed${NC}"
fi

if [ "$RESULT_SUBMITTED" = "true" ]; then
    echo -e "${GREEN}✓ Result was submitted${NC}"
else
    echo -e "${RED}✗ Result was NOT submitted${NC}"
fi
echo ""

# Step 6: Solutions
echo "=========================================="
echo "Solutions"
echo "=========================================="
echo ""

if [ "$TIMED_OUT" = "true" ]; then
    echo -e "${YELLOW}Solution 1: Reset Timed-Out DKG (Recommended)${NC}"
    echo ""
    echo "The DKG has timed out. Reset it to IDLE:"
    echo ""
    echo "  ./scripts/reset-dkg-if-timed-out.sh"
    echo ""
    echo "Or manually:"
    echo "  WR=\$(jq -r '.address' solidity/ecdsa/deployments/development/WalletRegistry.json)"
    echo "  ACCOUNT=\$(cast rpc eth_accounts --rpc-url $RPC_URL | jq -r '.[0]')"
    echo "  cast send \$WR \"notifyDkgTimeout()\" --rpc-url $RPC_URL --unlocked --from \$ACCOUNT"
    echo ""
    
    read -p "Do you want to reset the DKG now? (y/n): " reset_now
    if [ "$reset_now" = "y" ]; then
        echo ""
        echo "Resetting DKG..."
        WR=$(jq -r '.address' solidity/ecdsa/deployments/development/WalletRegistry.json)
        ACCOUNT=$(cast rpc eth_accounts --rpc-url "$RPC_URL" | jq -r '.[0]')
        
        if [ -n "$WR" ] && [ -n "$ACCOUNT" ]; then
            TX_HASH=$(cast send "$WR" "notifyDkgTimeout()" \
              --rpc-url "$RPC_URL" \
              --unlocked \
              --from "$ACCOUNT" \
              --gas-limit 300000 2>&1 | grep -oP 'transactionHash: \K[0-9a-fx]+' || echo "")
            
            if [ -n "$TX_HASH" ]; then
                echo -e "${GREEN}✓ Reset transaction submitted: $TX_HASH${NC}"
                sleep 3
                
                NEW_STATE=$(KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry get-wallet-creation-state \
                  --config "$CONFIG_FILE" --developer 2>&1 | grep -E "^[0-9]+$" | head -1 || echo "")
                
                if [ "$NEW_STATE" = "0" ]; then
                    echo -e "${GREEN}✓ DKG successfully reset to IDLE${NC}"
                    echo ""
                    echo "You can now trigger a new DKG:"
                    echo "  ./scripts/request-new-wallet.sh"
                else
                    echo -e "${YELLOW}⚠ DKG state is now: $NEW_STATE${NC}"
                fi
            else
                echo -e "${RED}✗ Failed to submit reset transaction${NC}"
            fi
        else
            echo -e "${RED}✗ Could not get WalletRegistry address or account${NC}"
        fi
    fi
    echo ""
fi

echo -e "${YELLOW}Solution 2: Increase Timeout (Prevent Future Issues)${NC}"
echo ""
echo "The current timeout ($SUBMISSION_TIMEOUT blocks) is too short."
echo "Increase it via governance to prevent future timeouts:"
echo ""
echo "  cd solidity/ecdsa"
echo "  # Update resultSubmissionTimeout to at least 500 blocks"
echo "  # This requires governance delay"
echo ""
echo "Or use the set-minimum-dkg-params script which sets reasonable values:"
echo "  ./scripts/set-minimum-dkg-params.sh"
echo ""

echo -e "${YELLOW}Solution 3: Check Why Protocol Isn't Completing${NC}"
echo ""
echo "Investigate why DKG protocol isn't completing:"
echo ""
echo "1. Check for errors in logs:"
echo "   tail -100 logs/node*.log | grep -i 'error\|fail'"
echo ""
echo "2. Check network connectivity between nodes:"
echo "   # Ensure nodes can communicate via libp2p"
echo ""
echo "3. Verify all operators are participating:"
echo "   tail -f logs/node*.log | grep -i 'member.*participating\|selected.*group'"
echo ""
echo "4. Check if protocol phases are completing:"
echo "   tail -f logs/node*.log | grep -E 'phase|announcement|key.*generation'"
echo ""

echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
echo "Current Status:"
echo "  - State: AWAITING_RESULT (2)"
echo "  - Timed Out: $TIMED_OUT"
echo "  - Timeout: $SUBMISSION_TIMEOUT blocks"
echo ""
echo "Recommended Action:"
if [ "$TIMED_OUT" = "true" ]; then
    echo "  1. Reset the timed-out DKG (Solution 1)"
    echo "  2. Increase timeout to prevent future issues (Solution 2)"
    echo "  3. Trigger new DKG: ./scripts/request-new-wallet.sh"
else
    echo "  1. Wait a bit more - timeout may not have fully passed"
    echo "  2. Check logs for protocol progress"
    echo "  3. If still stuck, increase timeout (Solution 2)"
fi
echo ""
