#!/bin/bash
# Script to transfer ownership of OLD EcdsaSortitionPool to WalletRegistry
# Uses Geth's debug API to impersonate the owner account

set -e

OLD_SP="0x6085ff3bcFA73aB7B1e244286c712E5f82FdB48A"
WALLET_REGISTRY="0x50E550fDEAC9DEFEf3Bb3a03cb0Fa1d4C37Af5ab"
CURRENT_OWNER="0xf40c5B4749991Bf5C5E5a78dAD469A980402a0a3"

echo "=========================================="
echo "Fixing OLD EcdsaSortitionPool Ownership"
echo "=========================================="
echo ""
echo "Old EcdsaSortitionPool: $OLD_SP"
echo "Current owner: $CURRENT_OWNER"
echo "Target owner: $WALLET_REGISTRY"
echo ""
echo "Using Geth's debug API to impersonate owner..."
echo ""

# Use cast to impersonate and transfer ownership
# First, check if debug API is available
if cast rpc debug_traceCall --rpc-url http://localhost:8545 > /dev/null 2>&1; then
  echo "Debug API available, using cast with impersonation..."
  
  # Impersonate the owner account
  echo "Note: This requires Geth to be started with --allow-insecure-unlock and debug API enabled"
  echo "If impersonation doesn't work, you'll need to import the owner's private key"
  echo ""
  
  # Try using cast with --unlocked (won't work if account not in keystore)
  cast send $OLD_SP "transferOwnership(address)" $WALLET_REGISTRY \
    --rpc-url http://localhost:8545 \
    --unlocked \
    --from $CURRENT_OWNER 2>&1 || {
    echo ""
    echo "⚠️  Could not transfer ownership automatically"
    echo ""
    echo "The owner account ($CURRENT_OWNER) is not in Geth's keystore."
    echo ""
    echo "Options:"
    echo "1. Import the owner's private key into Geth:"
    echo "   geth account import --keystore ~/ethereum/data/keystore <keyfile>"
    echo ""
    echo "2. Or use the NEW EcdsaSortitionPool by redeploying WalletRegistry:"
    echo "   cd solidity/ecdsa"
    echo "   rm -f deployments/development/WalletRegistry.json"
    echo "   npx hardhat deploy --network development --tags WalletRegistry"
    echo ""
    exit 1
  }
else
  echo "Debug API not available. Please use one of the options below."
  echo ""
  echo "Option 1: Import owner's private key and transfer ownership"
  echo "Option 2: Redeploy WalletRegistry to use the new EcdsaSortitionPool"
  exit 1
fi

echo ""
echo "=========================================="
echo "Done!"
echo "=========================================="
