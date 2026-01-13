#!/bin/bash
# Test each step of approval to find where it fails

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
echo "Testing Approval Steps"
echo "=========================================="
echo ""

# Get event data
EVENT_DATA=$(cast logs --from-block $SUBMISSION_BLOCK --to-block $SUBMISSION_BLOCK \
    "DkgResultSubmitted(bytes32 indexed,uint256 indexed,(uint256,bytes,uint8[],bytes,uint256[],uint32[],bytes32))" \
    --address "$WALLET_REGISTRY" --rpc-url "$RPC_URL" 2>/dev/null | head -1 || echo "")

if [ -z "$EVENT_DATA" ]; then
    echo -e "${RED}No event found${NC}"
    exit 1
fi

# Extract result hash
RESULT_HASH=$(echo "$EVENT_DATA" | grep -o "0x[a-f0-9]\{64\}" | head -2 | tail -1)
echo -e "${CYAN}Result Hash:${NC} $RESULT_HASH"
echo ""

# Check if wallet already exists
echo -e "${BLUE}Step 1: Checking if wallet already exists...${NC}"
# We need to calculate walletID from groupPubKey
# For now, let's check if we can call a function that would tell us

# Check SortitionPool state
echo -e "${BLUE}Step 2: Checking SortitionPool state...${NC}"
SORTITION_POOL="0x88b2480f0014ED6789690C1c4F35Fc230ef83458"
IS_LOCKED=$(cast call "$SORTITION_POOL" "isLocked()(bool)" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
echo "SortitionPool locked: $IS_LOCKED"
echo ""

# Check WalletOwner
echo -e "${BLUE}Step 3: Checking WalletOwner...${NC}"
WALLET_OWNER="0xc0a2ee534F004a4ec2EFA541489acBD5ff4bBA99"
OWNER_CODE=$(cast code "$WALLET_OWNER" --rpc-url "$RPC_URL" 2>/dev/null | head -c 20 || echo "")
if [ -n "$OWNER_CODE" ] && [ "$OWNER_CODE" != "0x" ]; then
    echo -e "${GREEN}WalletOwner is a contract${NC}"
    
    # Try to check if the callback function exists
    # The function signature is: __ecdsaWalletCreatedCallback(bytes32,bytes32,bytes32)
    CALLBACK_SIG="0x$(cast sig "__ecdsaWalletCreatedCallback(bytes32,bytes32,bytes32)" | cut -d' ' -f1)"
    echo "Callback signature: $CALLBACK_SIG"
    
    # Check if function exists in bytecode
    if echo "$OWNER_CODE" | grep -q "${CALLBACK_SIG:2:8}"; then
        echo -e "${GREEN}Callback function exists${NC}"
    else
        echo -e "${YELLOW}Could not verify callback function${NC}"
    fi
else
    echo -e "${RED}WalletOwner is not a contract!${NC}"
fi
echo ""

# Check ReimbursementPool
echo -e "${BLUE}Step 4: Checking ReimbursementPool...${NC}"
REIMBURSEMENT_POOL=$(cast call "$WALLET_REGISTRY" "reimbursementPool()(address)" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
if [ -n "$REIMBURSEMENT_POOL" ]; then
    echo "ReimbursementPool: $REIMBURSEMENT_POOL"
    POOL_CODE=$(cast code "$REIMBURSEMENT_POOL" --rpc-url "$RPC_URL" 2>/dev/null | head -c 20 || echo "")
    if [ -n "$POOL_CODE" ] && [ "$POOL_CODE" != "0x" ]; then
        echo -e "${GREEN}ReimbursementPool is a contract${NC}"
    else
        echo -e "${RED}ReimbursementPool is not a contract!${NC}"
    fi
fi
echo ""

# Summary
echo -e "${BLUE}=== Analysis ===${NC}"
echo ""
echo "The approveDkgResult function executes these steps:"
echo "  1. dkg.approveResult() - ✓ (would have error message if failed)"
echo "  2. wallets.addWallet() - storage write"
echo "  3. emit WalletCreated"
echo "  4. sortitionPool.setRewardIneligibility() - if misbehavedMembers.length > 0"
echo "  5. walletOwner.__ecdsaWalletCreatedCallback() - EXTERNAL CALL ⚠️"
echo "  6. dkg.complete()"
echo "  7. reimbursementPool.refund()"
echo ""
echo -e "${YELLOW}Most likely revert points (empty error):${NC}"
echo "  1. Array bounds error in approveResult (line 352, 371-373)"
echo "     - Accessing result.members[result.submitterMemberIndex - 1]"
echo "     - Accessing result.members[result.misbehavedMembersIndices[i] - 1]"
echo "  2. WalletOwner callback revert (external call)"
echo "  3. Out of gas (unlikely, but possible)"
echo ""
echo "The empty revert (0x) suggests:"
echo "  - assert() failure (no message)"
echo "  - Array bounds violation"
echo "  - External call revert without message"
echo "  - Arithmetic underflow/overflow"


