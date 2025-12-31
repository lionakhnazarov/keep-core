#!/bin/bash
# Script to check DKG status using multiple methods

set -e

cd "$(dirname "$0")/.."

cd solidity/ecdsa

echo "Checking DKG status..."
npx hardhat run scripts/check-dkg-status.ts --network development

cd ../..
