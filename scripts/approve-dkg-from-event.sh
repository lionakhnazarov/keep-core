#!/bin/bash
# Script to approve DKG result using exact data from submission event
# This bypasses hash mismatch issues by using the exact same structure

set -eou pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "=========================================="
echo "Approve DKG Result from Event"
echo "=========================================="
echo ""

cd solidity/ecdsa

echo "Running approval script..."
echo ""

npx hardhat run scripts/approve-dkg-from-event.ts --network development 2>&1 | grep -vE "(You are using|Please, make sure|To learn more|Error encountered|No need to generate|Contract Name|Size|Compiled|Compiling|^ ·|^ \||^---)"

