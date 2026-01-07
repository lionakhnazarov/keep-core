#!/bin/bash
# Script to check DKG approval status and diagnose why approval might fail

set -e

cd "$(dirname "$0")/.."

RPC_URL="${RPC_URL:-http://localhost:8545}"

echo "=========================================="
echo "DKG Approval Status Check"
echo "=========================================="
echo "RPC URL: $RPC_URL"
echo ""

cd solidity/ecdsa

# Get current block number
CURRENT_BLOCK=$(curl -s -X POST \
  -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  "$RPC_URL" | grep -o '"result":"0x[0-9a-f]*"' | cut -d'"' -f4 | xargs printf "%d\n")

echo "Current Block: $CURRENT_BLOCK"
echo ""

# Run the TypeScript check script
npx hardhat run scripts/check-dkg-approval-status.ts --network development

echo ""
echo "=========================================="
echo "Common reasons for 'execution reverted':"
echo "=========================================="
echo "1. Challenge period hasn't passed yet"
echo "2. Not the submitter and trying during precedence period"
echo "3. DKG state is not CHALLENGE"
echo "4. Result hash doesn't match submitted result"
echo "5. Result already approved"
echo ""

