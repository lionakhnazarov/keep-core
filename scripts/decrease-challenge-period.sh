#!/bin/bash
# Script to decrease the DKG Result Challenge Period Length
# This requires a two-step governance process with a delay

set -e

cd "$(dirname "$0")/.."

# Default to 100 blocks if not specified (minimum is 10)
NEW_VALUE=${1:-100}

if [ "$NEW_VALUE" -lt 10 ]; then
  echo "Error: Challenge period length must be >= 10 blocks"
  echo "Usage: $0 [NEW_VALUE_IN_BLOCKS]"
  echo "Example: $0 100  (sets challenge period to 100 blocks)"
  exit 1
fi

echo "=========================================="
echo "Decrease DKG Challenge Period Length"
echo "=========================================="
echo ""
echo "New value: $NEW_VALUE blocks"
echo "  (~$((NEW_VALUE * 15 / 60)) minutes at 15s/block)"
echo ""

cd solidity/ecdsa

# Run the update script
NEW_VALUE=$NEW_VALUE npx hardhat run scripts/update-result-challenge-period-length.ts --network development
