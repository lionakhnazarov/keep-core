#!/bin/bash
# Script to get DKG result JSON from various sources
# Usage: ./scripts/get-dkg-result.sh [config-file]
#
# This script attempts to retrieve the DKG result JSON from:
# 1. Node logs (most reliable)
# 2. On-chain events (DkgResultSubmitted)
# 3. Hardhat console queries

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
echo "Get DKG Result JSON"
echo "=========================================="
echo ""

# Method 1: Check node logs for DKG result submission
echo -e "${BLUE}Method 1: Searching node logs for DKG result...${NC}"
echo ""

DKG_RESULT_FOUND=false
RESULT_LOG_FILE=""

for i in {1..10}; do
    LOG_FILE="logs/node${i}.log"
    if [ ! -f "$LOG_FILE" ]; then
        continue
    fi
    
    # Look for DKG result submission messages
    # The result is logged when nodes receive the DkgResultSubmitted event
    if grep -q "DKG.*result.*submitted\|Result with hash.*for DKG\|submitted DKG result" "$LOG_FILE" 2>/dev/null; then
        echo -e "${GREEN}✓ Found DKG result submission in node $i logs${NC}"
        RESULT_LOG_FILE="$LOG_FILE"
        DKG_RESULT_FOUND=true
        
        # Try to extract relevant information
        echo ""
        echo "Relevant log entries:"
        grep -i "DKG.*result.*submitted\|Result with hash.*for DKG\|submitted DKG result\|resultHash\|GroupPublicKey" "$LOG_FILE" 2>/dev/null | tail -10 | head -5
        echo ""
        break
    fi
done

if [ "$DKG_RESULT_FOUND" = "false" ]; then
    echo -e "${YELLOW}⚠ No DKG result submission found in logs${NC}"
    echo ""
else
    echo "The DKG result JSON is embedded in the DkgResultSubmitted event."
    echo "However, the full JSON structure may not be directly logged."
    echo ""
fi

# Method 2: Query on-chain events
echo -e "${BLUE}Method 2: Querying on-chain DkgResultSubmitted events...${NC}"
echo ""

# Get WalletRegistry address
WALLET_REGISTRY_ADDR=$(grep -E "^WalletRegistry\s*=" "$CONFIG_FILE" 2>/dev/null | head -1 | cut -d'=' -f2 | tr -d ' "' || echo "")

if [ -z "$WALLET_REGISTRY_ADDR" ]; then
    # Try to get from contract addresses section
    WALLET_REGISTRY_ADDR=$(grep -A 20 "\[ethereum.contractAddresses\]" "$CONFIG_FILE" 2>/dev/null | grep -i "WalletRegistry" | cut -d'=' -f2 | tr -d ' "' || echo "")
fi

if [ -n "$WALLET_REGISTRY_ADDR" ]; then
    echo "WalletRegistry address: $WALLET_REGISTRY_ADDR"
    echo ""
    echo "Querying DkgResultSubmitted events using Hardhat..."
    echo ""
    
    # Use Hardhat to query events
    cd solidity/ecdsa
    
    EVENT_QUERY=$(cat <<'EOF'
const { ethers, helpers } = require("hardhat");
(async () => {
  try {
    const wr = await helpers.contracts.getContract("WalletRegistry");
    const filter = wr.filters.DkgResultSubmitted();
    const events = await wr.queryFilter(filter);
    
    if (events.length === 0) {
      console.log("No DkgResultSubmitted events found");
      process.exit(0);
    }
    
    const latestEvent = events[events.length - 1];
    console.log("\n=== Latest DKG Result Submission ===");
    console.log("Block:", latestEvent.blockNumber.toString());
    console.log("Transaction:", latestEvent.transactionHash);
    console.log("Result Hash:", latestEvent.args.resultHash);
    console.log("Seed:", latestEvent.args.seed.toString());
    
    // The result object is in args.result
    const result = latestEvent.args.result;
    console.log("\n=== DKG Result ===");
    console.log("Submitter Member Index:", result.submitterMemberIndex.toString());
    console.log("Group Public Key:", result.groupPubKey);
    console.log("Misbehaved Members Indices:", result.misbehavedMembersIndices.map(x => x.toString()));
    console.log("Signatures:", result.signatures);
    console.log("Signing Members Indices:", result.signingMembersIndices.map(x => x.toString()));
    console.log("Members:", result.members.map(x => x.toString()));
    
    // Format as JSON for approval command
    // IMPORTANT: Use numeric values (not strings) for *big.Int and uint32 fields
    console.log("\n=== JSON for approve-dkg-result command ===");
    const dkgResultJson = {
      submitterMemberIndex: result.submitterMemberIndex.toNumber(),
      groupPubKey: result.groupPubKey,
      misbehavedMembersIndices: result.misbehavedMembersIndices.map(x => Number(x)),
      signatures: result.signatures,
      signingMembersIndices: result.signingMembersIndices.map(x => x.toNumber()),
      members: result.members.map(x => Number(x)),
      membersHash: result.membersHash || "0x0000000000000000000000000000000000000000000000000000000000000000"
    };
    console.log(JSON.stringify(dkgResultJson, null, 2));
    
    process.exit(0);
  } catch (error) {
    console.error("Error:", error.message);
    process.exit(1);
  }
})();
EOF
)
    
    echo "$EVENT_QUERY" | npx hardhat console --network development 2>&1 | grep -A 100 "=== Latest DKG Result Submission ===" || {
        echo -e "${YELLOW}⚠ Could not query events via Hardhat${NC}"
        echo "Make sure Hardhat is set up and network is running"
    }
    
    cd ../..
else
    echo -e "${YELLOW}⚠ Could not find WalletRegistry address in config${NC}"
fi

echo ""

# Method 3: Instructions for manual extraction
echo -e "${BLUE}Method 3: Manual extraction instructions...${NC}"
echo ""
echo "If automatic extraction fails, you can manually get the DKG result:"
echo ""
echo "1. Find the DkgResultSubmitted event transaction:"
echo "   - Check node logs for 'DKG result submitted' messages"
echo "   - Note the transaction hash"
echo ""
echo "2. Query the event using Hardhat:"
echo "   cd solidity/ecdsa"
echo "   npx hardhat console --network development"
echo ""
echo "   Then run:"
echo "   const wr = await helpers.contracts.getContract('WalletRegistry');"
echo "   const events = await wr.queryFilter(wr.filters.DkgResultSubmitted());"
echo "   const latest = events[events.length - 1];"
echo "   console.log(JSON.stringify(latest.args.result, null, 2));"
echo ""
echo "3. Or query via JSON-RPC:"
echo "   Use eth_getLogs with:"
echo "   - address: WalletRegistry contract address"
echo "   - topics: [DkgResultSubmitted event signature]"
echo ""
echo "4. Extract from node logs (if logged):"
echo "   grep -i 'result.*submitted\|groupPubKey\|submitterMemberIndex' logs/node*.log"
echo ""

# Method 4: Check if result is stored in contract
echo -e "${BLUE}Method 4: Checking contract storage...${NC}"
echo ""
echo "Note: The contract stores only the result hash, not the full JSON."
echo "You need the exact result JSON that was submitted."
echo ""
echo "The result hash can be verified with:"
echo "  keccak256(abi.encode(result))"
echo ""

echo "=========================================="
echo -e "${GREEN}Summary${NC}"
echo "=========================================="
echo ""
echo "The DKG result JSON must match exactly what was submitted."
echo "Best sources:"
echo "  1. On-chain DkgResultSubmitted event (most reliable)"
echo "  2. Node logs (if they logged the full result)"
echo "  3. Hardhat console query (see Method 2)"
echo ""
echo "Once you have the JSON, use:"
echo "  KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry approve-dkg-result '<json>' \\"
echo "    --submit --config $CONFIG_FILE --developer"
echo ""

