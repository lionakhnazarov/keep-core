#!/bin/bash
# Script to request a new wallet (trigger DKG) via the Bridge contract
# This works because Bridge is the walletOwner and has a requestNewWallet() function

set -e

cd "$(dirname "$0")/.."

cd solidity/ecdsa

npx hardhat run scripts/request-new-wallet.ts --network development

cd ../..
