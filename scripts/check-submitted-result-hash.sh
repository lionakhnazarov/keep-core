#!/bin/bash
# Extract and verify the submitted DKG result hash from events

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
echo "Checking Submitted DKG Result Hash"
echo "=========================================="
echo "RPC URL: $RPC_URL"
echo "WalletRegistry: $WALLET_REGISTRY"
echo "Submission Block: $SUBMISSION_BLOCK"
echo "=========================================="
echo ""

# Get the event at the submission block
echo -e "${BLUE}Extracting DkgResultSubmitted event from block $SUBMISSION_BLOCK...${NC}"

# Get the event - the first indexed parameter is the resultHash
EVENT_DATA=$(cast logs --from-block $SUBMISSION_BLOCK --to-block $SUBMISSION_BLOCK \
    "DkgResultSubmitted(bytes32 indexed,uint256 indexed,(uint256,bytes,uint8[],bytes,uint256[],uint32[],bytes32))" \
    --address "$WALLET_REGISTRY" --rpc-url "$RPC_URL" 2>/dev/null | head -1 || echo "")

if [ -z "$EVENT_DATA" ]; then
    echo -e "${RED}No event found at block $SUBMISSION_BLOCK${NC}"
    exit 1
fi

# Extract the result hash (first topic after event signature)
RESULT_HASH=$(echo "$EVENT_DATA" | grep -oP 'topics:\s+\[0x[^,]+,\s+0x([^,]+)' | sed -n 's/.*0x\([^,]*\).*/\1/p' | head -1)
if [ -z "$RESULT_HASH" ]; then
    # Try alternative extraction
    RESULT_HASH=$(echo "$EVENT_DATA" | grep -oP '0x[a-f0-9]{64}' | head -2 | tail -1)
fi

if [ -n "$RESULT_HASH" ]; then
    echo -e "${GREEN}Submitted Result Hash:${NC} 0x$RESULT_HASH"
    echo ""
    echo -e "${CYAN}Expected Hash from logs:${NC} 0x4020d2456623b188c9f5a0692e0938fbf59658b8f7f89a1b743db7c416ff822e"
    echo ""
    
    # Normalize both hashes for comparison
    NORMALIZED_EVENT=$(echo "0x$RESULT_HASH" | tr '[:upper:]' '[:lower:]')
    NORMALIZED_EXPECTED=$(echo "0x4020d2456623b188c9f5a0692e0938fbf59658b8f7f89a1b743db7c416ff822e" | tr '[:upper:]' '[:lower:]')
    
    if [ "$NORMALIZED_EVENT" = "$NORMALIZED_EXPECTED" ]; then
        echo -e "${GREEN}✓ Hashes match!${NC}"
    else
        echo -e "${RED}✗ Hash mismatch!${NC}"
        echo ""
        echo -e "${YELLOW}This is likely the cause of the approval revert.${NC}"
        echo "The result being approved doesn't match what was submitted."
    fi
else
    echo -e "${YELLOW}Could not extract result hash from event${NC}"
    echo "Event data:"
    echo "$EVENT_DATA"
fi

echo ""
echo -e "${BLUE}=== Diagnosis ===${NC}"
echo "If hashes don't match, the approval will revert with:"
echo '  "Result under approval is different than the submitted one"'
echo ""
echo "Possible causes:"
echo "  1. Result encoding mismatch (ABI encoding differences)"
echo "  2. Result data was modified between submission and approval"
echo "  3. Different result structure being used"
echo ""
echo "To fix:"
echo "  1. Verify the exact result structure used during submission"
echo "  2. Ensure the same encoding method is used for approval"
echo "  3. Check if there's a hash encoding issue in the Go code"


