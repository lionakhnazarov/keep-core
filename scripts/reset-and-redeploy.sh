#!/bin/bash
# Script to reset the development chain and redeploy all contracts with ExtendedTokenStaking

set -e

echo "⚠️  WARNING: This will delete all chain data and redeploy all contracts!"
echo "Press Ctrl+C to cancel, or Enter to continue..."
read

# Check if Geth is running
if pgrep -f "geth.*8545" > /dev/null; then
    echo "Stopping Geth..."
    pkill -f "geth.*8545" || true
    sleep 2
fi

# Delete chaindata
if [ -d "$HOME/ethereum/data/geth" ]; then
    echo "Deleting chaindata..."
    rm -rf "$HOME/ethereum/data/geth"
    echo "✓ Chaindata deleted"
else
    echo "No chaindata found, skipping deletion"
fi

# Delete deployment files to force fresh deployment
echo "Cleaning deployment files..."
cd "$(dirname "$0")/../solidity/random-beacon"
rm -f deployments/development/*.json 2>/dev/null || true
echo "✓ RandomBeacon deployments cleaned"

cd "../ecdsa"
rm -f deployments/development/*.json 2>/dev/null || true
echo "✓ ECDSA deployments cleaned"

echo ""
echo "✓ Reset complete!"
echo ""
echo "Next steps:"
echo "1. Start Geth (if not already running)"
echo "2. Wait for Geth to start mining"
echo "3. Unlock accounts (if needed):"
echo "   cast rpc eth_accounts --rpc-url http://localhost:8545 | jq -r '.[]' | while read addr; do cast rpc \"personal_unlockAccount\" [\"$addr\",\"\",0] --rpc-url http://localhost:8545 || true; done"
echo "4. Deploy T token: cd tmp/solidity-contracts && yarn deploy --network development --reset"
echo "5. Deploy ECDSA contracts: cd ../../solidity/ecdsa && npx hardhat deploy --network development"
echo "6. Deploy RandomBeacon: cd ../random-beacon && npx hardhat deploy --network development --tags RandomBeacon"
echo "7. Run initialize script: cd ../../ && ./scripts/initialize.sh --network development"
