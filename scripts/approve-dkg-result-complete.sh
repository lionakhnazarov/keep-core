#!/bin/bash
# Script to approve DKG result stuck in CHALLENGE state
# Usage: ./scripts/approve-dkg-result-complete.sh [config-file] [node-number]
#
# This script:
# 1. Checks DKG is in CHALLENGE state
# 2. Verifies challenge period has passed
# 3. Gets the DKG result JSON from on-chain events
# 4. Approves the DKG result using the operator key from specified node

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

CONFIG_FILE=${1:-"configs/config.toml"}
NODE_NUM=${2:-"1"}

echo "=========================================="
echo "Approve DKG Result (Complete Process)"
echo "=========================================="
echo ""
echo "Config: $CONFIG_FILE"
echo "Node: $NODE_NUM"
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
    if [ "$CURRENT_STATE" = "0" ]; then
        echo "DKG is already complete (IDLE state)."
    elif [ "$CURRENT_STATE" = "2" ]; then
        echo "DKG is still awaiting result submission. Wait for result to be submitted first."
    else
        echo "DKG is in state: $STATE_NAME. Approval only works in CHALLENGE state."
    fi
    exit 1
fi

echo -e "${GREEN}✓ DKG is in CHALLENGE state${NC}"
echo ""

# Step 2: Check challenge period
echo -e "${BLUE}Step 2: Checking challenge period status...${NC}"
cd solidity/ecdsa

TIMING_CHECK=$(cat <<'EOF'
const { ethers, helpers } = require("hardhat");
(async () => {
  try {
    const wr = await helpers.contracts.getContract("WalletRegistry");
    const currentBlock = await ethers.provider.getBlockNumber();
    const params = await wr.dkgParameters();
    
    const filter = wr.filters.DkgResultSubmitted();
    const events = await wr.queryFilter(filter, -2000);
    
    if (events.length === 0) {
      console.log("ERROR: No DkgResultSubmitted events found");
      process.exit(1);
    }
    
    const latestEvent = events[events.length - 1];
    const submissionBlock = latestEvent.blockNumber;
    // Convert BigNumbers to numbers for proper addition
    const submissionBlockNum = Number(submissionBlock);
    const challengePeriodLengthNum = Number(params.resultChallengePeriodLength);
    const precedencePeriodLengthNum = Number(params.submitterPrecedencePeriodLength);
    
    const challengePeriodEnd = submissionBlockNum + challengePeriodLengthNum;
    const precedencePeriodEnd = challengePeriodEnd + precedencePeriodLengthNum;
    
    console.log("Current Block:", currentBlock);
    console.log("Submission Block:", submissionBlockNum);
    console.log("Challenge Period End:", challengePeriodEnd);
    console.log("Precedence Period End:", precedencePeriodEnd);
    console.log("Challenge Period Length:", challengePeriodLengthNum);
    console.log("Precedence Period Length:", precedencePeriodLengthNum);
    
    if (currentBlock <= challengePeriodEnd) {
      console.log("STATUS: Challenge period has NOT passed");
      console.log("Blocks remaining:", (challengePeriodEnd - currentBlock).toString());
      process.exit(1);
    } else if (currentBlock <= precedencePeriodEnd) {
      console.log("STATUS: Challenge period PASSED, but in precedence period");
      console.log("Only submitter can approve. Blocks remaining:", (precedencePeriodEnd - currentBlock).toString());
    } else {
      console.log("STATUS: Challenge and precedence periods PASSED");
      console.log("Any eligible member can approve");
    }
    
    process.exit(0);
  } catch (error) {
    console.error("ERROR:", error.message);
    process.exit(1);
  }
})();
EOF
)

TIMING_OUTPUT=$(echo "$TIMING_CHECK" | npx hardhat console --network development 2>&1 | grep -A 20 "Current Block:" || echo "")

if [ -z "$TIMING_OUTPUT" ]; then
    echo -e "${YELLOW}⚠ Could not check timing via Hardhat${NC}"
    echo "Proceeding anyway..."
else
    echo "$TIMING_OUTPUT"
    echo ""
    
    if echo "$TIMING_OUTPUT" | grep -q "Challenge period has NOT passed"; then
        echo -e "${RED}✗ Challenge period has not passed yet${NC}"
        echo ""
        echo "You need to wait for the challenge period to end before approving."
        echo "Or mine blocks to advance time:"
        echo "  ./scripts/mine-blocks-fast.sh [number_of_blocks]"
        exit 1
    fi
fi

cd ../..
echo ""

# Step 3: Get DKG result JSON
echo -e "${BLUE}Step 3: Getting DKG result JSON from on-chain events...${NC}"
cd solidity/ecdsa

# Generate JSON and write to temp file
TEMP_JSON_OUTPUT=$(mktemp)
TEMP_SCRIPT=$(mktemp)
cat > "$TEMP_SCRIPT" <<'EOF'
const { ethers, helpers } = require("hardhat");
(async () => {
  const wr = await helpers.contracts.getContract("WalletRegistry");
  const filter = wr.filters.DkgResultSubmitted();
  const events = await wr.queryFilter(filter, -2000);
  const latestEvent = events[events.length - 1];
  const result = latestEvent.args.result;
  const dkgResultJson = {
    SubmitterMemberIndex: result.submitterMemberIndex.toString(),
    GroupPubKey: result.groupPubKey,
    MisbehavedMembersIndices: result.misbehavedMembersIndices.map(x => Number(x)),
    Signatures: result.signatures,
    SigningMembersIndices: result.signingMembersIndices.map(x => x.toString()),
    Members: result.members.map(x => Number(x)),
    MembersHash: result.membersHash || "0x0000000000000000000000000000000000000000000000000000000000000000"
  };
  console.log(JSON.stringify(dkgResultJson));
  process.exit(0);
})();
EOF

# Extract JSON from output - save to file first, then extract
TEMP_FULL_OUTPUT=$(mktemp)
npx hardhat console --network development < "$TEMP_SCRIPT" 2>&1 > "$TEMP_FULL_OUTPUT"
rm "$TEMP_SCRIPT"

# Extract JSON using python - read from file
python3 <<PYTHON_SCRIPT > "$TEMP_JSON_OUTPUT" 2>/dev/null
import sys
import json

try:
    with open('$TEMP_FULL_OUTPUT', 'r') as f:
        for line in f:
            line = line.strip()
            if line.startswith('{') and 'SubmitterMemberIndex' in line:
                try:
                    parsed = json.loads(line)
                    if 'GroupPubKey' in parsed and 'SubmitterMemberIndex' in parsed:
                        print(line)
                        sys.exit(0)
                except json.JSONDecodeError:
                    continue
                except:
                    continue
except:
    pass
sys.exit(1)
PYTHON_SCRIPT
rm "$TEMP_FULL_OUTPUT"

if [ -s "$TEMP_JSON_OUTPUT" ]; then
    DKG_RESULT_JSON=$(cat "$TEMP_JSON_OUTPUT")
    rm "$TEMP_JSON_OUTPUT"
else
    rm "$TEMP_JSON_OUTPUT"
    echo -e "${RED}✗ Failed to extract JSON${NC}"
    echo ""
    echo "Try running manually:"
    echo "  cd solidity/ecdsa"
    echo "  npx hardhat console --network development"
    echo "  Then run the script from get-dkg-result.sh"
    exit 1
fi

cd ../..

if [ -z "$DKG_RESULT_JSON" ] || ! echo "$DKG_RESULT_JSON" | grep -q "groupPubKey"; then
    echo -e "${RED}✗ Failed to get DKG result JSON${NC}"
    echo ""
    echo "Try running manually:"
    echo "  ./scripts/get-dkg-result.sh $CONFIG_FILE"
    exit 1
fi

echo -e "${GREEN}✓ DKG result JSON retrieved${NC}"
echo ""
echo "Result preview:"
echo "$DKG_RESULT_JSON" | head -10
echo "..."
echo ""

# Step 4: Approve DKG result
echo -e "${BLUE}Step 4: Approving DKG result...${NC}"
echo ""
echo -e "${YELLOW}⚠ This will submit a transaction to approve the DKG result${NC}"
echo ""

# Use the config file for the specified node if it exists
NODE_CONFIG="configs/node${NODE_NUM}.toml"
if [ ! -f "$NODE_CONFIG" ]; then
    NODE_CONFIG="$CONFIG_FILE"
fi

echo "Using config: $NODE_CONFIG"
echo ""

# Save JSON to temp file to avoid shell escaping issues
TEMP_JSON=$(mktemp)
echo "$DKG_RESULT_JSON" > "$TEMP_JSON"

echo "Executing approval command..."
echo ""

APPROVAL_OUTPUT=$(KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry approve-dkg-result "$(cat "$TEMP_JSON")" \
  --submit --config "$NODE_CONFIG" --developer 2>&1 || echo "FAILED")

rm "$TEMP_JSON"

if echo "$APPROVAL_OUTPUT" | grep -qi "error\|failed\|revert"; then
    echo -e "${RED}✗ Approval failed${NC}"
    echo ""
    echo "Output:"
    echo "$APPROVAL_OUTPUT"
    echo ""
    echo "Common issues:"
    echo "  1. Challenge period hasn't passed"
    echo "  2. You're not the submitter and precedence period is active"
    echo "  3. Result hash mismatch"
    echo "  4. Operator not eligible to approve"
    echo ""
    echo "Check logs for more details:"
    echo "  tail -f logs/node${NODE_NUM}.log | grep -i approve"
    exit 1
fi

echo "$APPROVAL_OUTPUT"
echo ""

# Step 5: Verify approval
echo -e "${BLUE}Step 5: Verifying approval...${NC}"
sleep 2

NEW_STATE=$(KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry get-wallet-creation-state \
  --config "$CONFIG_FILE" --developer 2>&1 | grep -E "^[0-9]+$" | tail -1 || echo "")

NEW_STATE_NAME=$(get_state_name "$NEW_STATE")

echo "New DKG State: $NEW_STATE ($NEW_STATE_NAME)"
echo ""

if [ "$NEW_STATE" = "0" ]; then
    echo -e "${GREEN}✓✓✓ DKG Result Approved Successfully! ✓✓✓${NC}"
    echo ""
    echo "DKG is now complete (IDLE state)."
    echo "The wallet should be created and ready to use."
else
    echo -e "${YELLOW}⚠ State changed to: $NEW_STATE_NAME${NC}"
    echo ""
    echo "The approval transaction may still be pending."
    echo "Check transaction status and wait for confirmation."
fi

echo ""
echo "=========================================="
echo -e "${GREEN}Done!${NC}"
echo "=========================================="

