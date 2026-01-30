#!/bin/bash
# Script to register wallets in Bridge that were created via DKG
# but not automatically registered (because Bridge stub's callback is empty)

set -e

cd "$(dirname "$0")/.."

cd solidity/tbtc-stub

echo "Registering wallets in Bridge..."
npx hardhat run scripts/register-wallets-in-bridge.ts --network development

cd ../..
