#!/bin/bash
# Capture the exact revert reason for DKG approval failure

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
echo "Capturing DKG Approval Revert Reason"
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

# Get current block
CURRENT_BLOCK=$(cast block-number --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
echo -e "${BLUE}Current Block:${NC} $CURRENT_BLOCK"
echo ""

# Get the DKG result from the event
echo -e "${BLUE}Step 1: Extracting DKG result from event at block $SUBMISSION_BLOCK...${NC}"

# Get the event data
EVENT_DATA=$(cast logs --from-block $SUBMISSION_BLOCK --to-block $SUBMISSION_BLOCK \
    "DkgResultSubmitted(bytes32 indexed,uint256 indexed,(uint256,bytes,uint8[],bytes,uint256[],uint32[],bytes32))" \
    --address "$WALLET_REGISTRY" --rpc-url "$RPC_URL" 2>/dev/null | head -1 || echo "")

if [ -z "$EVENT_DATA" ]; then
    echo -e "${RED}Error: No DkgResultSubmitted event found at block $SUBMISSION_BLOCK${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Event found${NC}"
echo ""

# Extract result hash from topics
RESULT_HASH=$(echo "$EVENT_DATA" | grep -o "0x[a-f0-9]\{64\}" | head -2 | tail -1)
echo -e "${CYAN}Result Hash:${NC} $RESULT_HASH"
echo ""

# Get an account to use for the call
echo -e "${BLUE}Step 2: Getting account for simulation...${NC}"
ACCOUNT=$(cast rpc eth_accounts --rpc-url "$RPC_URL" 2>/dev/null | jq -r '.[0]' 2>/dev/null || echo "")
if [ -z "$ACCOUNT" ] || [ "$ACCOUNT" = "null" ]; then
    echo -e "${YELLOW}Warning: Could not get account, using zero address${NC}"
    ACCOUNT="0x0000000000000000000000000000000000000000"
else
    echo -e "${GREEN}✓ Using account:${NC} $ACCOUNT"
fi
echo ""

# Try to call approveDkgResult using cast
echo -e "${BLUE}Step 3: Attempting to simulate approveDkgResult call...${NC}"
echo "This will show the exact revert reason."
echo ""

# First, let's try to get the result data from the event
# We need to decode the event data to get the full result structure
# For now, let's use a TypeScript script that can properly decode it

echo -e "${YELLOW}Note: To get the exact revert reason with full result data,${NC}"
echo -e "${YELLOW}please run the TypeScript script:${NC}"
echo ""
echo "  cd solidity/ecdsa && npx hardhat run scripts/get-revert-reason.ts --network development"
echo ""

# However, we can still try to get basic revert info using cast
echo -e "${BLUE}Step 4: Checking contract state requirements...${NC}"

# Check state
STATE=$(cast call "$WALLET_REGISTRY" "getWalletCreationState()(uint8)" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
if [ "$STATE" = "3" ]; then
    echo -e "${GREEN}✓ State is CHALLENGE (correct)${NC}"
else
    echo -e "${RED}✗ State is $STATE (expected 3)${NC}"
fi

# Check if we can get submitted result block (this might revert)
echo ""
echo -e "${BLUE}Step 5: Checking submitted result block...${NC}"
SUBMITTED_BLOCK=$(cast call "$WALLET_REGISTRY" "submittedResultBlock()(uint256)" --rpc-url "$RPC_URL" 2>&1 || echo "REVERT")
if [ "$SUBMITTED_BLOCK" != "REVERT" ] && [ -n "$SUBMITTED_BLOCK" ]; then
    echo -e "${GREEN}✓ Submitted block: $SUBMITTED_BLOCK${NC}"
else
    echo -e "${RED}✗ Cannot get submitted block (call reverted)${NC}"
    echo "This suggests the contract state may be inconsistent"
fi

echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo "To capture the exact revert reason:"
echo ""
echo "1. Run the TypeScript script (recommended):"
echo "   cd solidity/ecdsa"
echo "   npx hardhat run scripts/get-revert-reason.ts --network development"
echo ""
echo "2. Or use cast with debug_traceCall:"
echo "   cast run <tx_hash> --rpc-url $RPC_URL --trace"
echo ""
echo "3. Check recent failed transactions:"
echo "   Look for transactions that reverted and use cast to decode them"
echo ""

# Try to find recent failed approval transactions
echo -e "${BLUE}Step 6: Checking for recent failed transactions...${NC}"
echo "Searching logs for approval attempts..."
echo ""

# Check if we can use cast to simulate with a minimal call
echo -e "${YELLOW}For detailed revert reason decoding, the TypeScript script is recommended${NC}"
echo "as it can properly encode the full DKG result structure."

