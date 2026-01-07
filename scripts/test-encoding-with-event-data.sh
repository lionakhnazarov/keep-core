#!/bin/bash
# Test encoding with actual event data from the chain
# This will extract the exact DKG result from the submission event
# and test if go-ethereum encoding matches the stored hash

set -eou pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=========================================="
echo "Test Encoding with Actual Event Data"
echo "=========================================="
echo ""

cd "$PROJECT_ROOT/solidity/ecdsa"

echo "Running debug script to extract event data..."
echo ""

# Run the debug script to get the actual event data
npx hardhat run scripts/debug-hash-mismatch.ts --network development 2>&1 | \
    grep -E "(Stored Hash|Submission Block|submitterMemberIndex|groupPubKey|membersHash|signatures|members)" | \
    head -20

echo ""
echo "=========================================="
echo "Next: Create a Go test that uses this exact data"
echo "=========================================="

