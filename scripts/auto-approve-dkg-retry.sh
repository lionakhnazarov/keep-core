#!/bin/bash
# Script to automatically retry DKG result approval
# This will keep trying until successful or manually stopped

set -eou pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

CONFIG_FILE=${1:-"configs/node2.toml"}  # Use node2 (submitter) by default
NODE_NUM=${2:-"2"}

echo "=========================================="
echo "Auto-Retry DKG Result Approval"
echo "=========================================="
echo "Config: $CONFIG_FILE"
echo "Node: $NODE_NUM"
echo ""
echo "This script will retry approval every 30 seconds"
echo "Press Ctrl+C to stop"
echo "=========================================="
echo ""

# Ensure JSON file exists
if [ ! -s /tmp/dkg-result-final.json ]; then
    echo "Generating DKG result JSON..."
    cd solidity/ecdsa
    cat <<'EOF' | npx hardhat console --network development 2>&1 | grep -E '^\{.*SubmitterMemberIndex' | head -1 > /tmp/dkg-result-final.json
const { ethers, helpers } = require("hardhat");
(async () => {
  const wr = await helpers.contracts.getContract("WalletRegistry");
  const filter = wr.filters.DkgResultSubmitted();
  const events = await wr.queryFilter(filter, -2000);
  const latestEvent = events[events.length - 1];
  const result = latestEvent.args.result;
  const dkgResultJson = {
    SubmitterMemberIndex: result.submitterMemberIndex.toNumber(),
    GroupPubKey: Buffer.from(result.groupPubKey.slice(2), "hex").toString("base64"),
    MisbehavedMembersIndices: result.misbehavedMembersIndices.map(x => Number(x)),
    Signatures: Buffer.from(result.signatures.slice(2), "hex").toString("base64"),
    SigningMembersIndices: result.signingMembersIndices.map(x => x.toNumber()),
    Members: result.members.map(x => Number(x)),
    MembersHash: Array.from(Buffer.from(result.membersHash.slice(2), "hex")).map(b => b)
  };
  console.log(JSON.stringify(dkgResultJson));
  process.exit(0);
})();
EOF
    cd ../..
fi

RETRY_COUNT=0
MAX_RETRIES=${MAX_RETRIES:-1000}

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "[Attempt $RETRY_COUNT] $(date '+%Y-%m-%d %H:%M:%S') - Attempting approval..."
    
    OUTPUT=$(KEEP_ETHEREUM_PASSWORD=password ./keep-client --config "$CONFIG_FILE" ethereum ecdsa wallet-registry approve-dkg-result "$(cat /tmp/dkg-result-final.json)" --submit --developer 2>&1) || true
    
    if echo "$OUTPUT" | grep -q "Transaction submitted\|already approved\|success"; then
        echo "✅ SUCCESS! DKG result approved!"
        echo "$OUTPUT"
        exit 0
    elif echo "$OUTPUT" | grep -q "execution reverted"; then
        echo "❌ Failed: execution reverted (will retry in 30 seconds...)"
        if [ $RETRY_COUNT -eq 1 ] || [ $((RETRY_COUNT % 10)) -eq 0 ]; then
            echo "   Full error output:"
            echo "$OUTPUT" | tail -5 | sed 's/^/   /'
        fi
    else
        echo "⚠️  Unexpected error:"
        echo "$OUTPUT" | tail -10
    fi
    
    sleep 30
done

echo "Reached maximum retries ($MAX_RETRIES). Stopping."


