#!/bin/bash
# Script to set DKG parameters to minimum values for development

set -eou pipefail

echo "=========================================="
echo "Set DKG Parameters to Minimum (Development)"
echo "=========================================="
echo ""

cd "$(dirname "$0")/../solidity/ecdsa"

echo "Running Hardhat script to set minimum DKG parameters..."
echo ""

npx hardhat run scripts/set-minimum-dkg-params.ts --network development

echo ""
echo "=========================================="
echo "Done!"
echo "=========================================="
echo ""
echo "DKG parameters have been set to minimum values:"
echo "  - seedTimeout: 8 blocks"
echo "  - resultChallengePeriodLength: 10 blocks"
echo "  - resultSubmissionTimeout: 30 blocks"
echo "  - submitterPrecedencePeriodLength: 5 blocks"
echo ""
echo "Note: These are minimum values suitable for development only."
echo "      Production values are much higher for security."
