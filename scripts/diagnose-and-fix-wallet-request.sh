#!/bin/bash
# Script to diagnose and fix wallet request issues
# This checks the actual state and provides working solutions

set -e

cd "$(dirname "$0")/.."

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "=========================================="
echo "Diagnosing Wallet Request Issue"
echo "=========================================="
echo ""

# Get addresses
BRIDGE_ADDRESS=""
WALLET_REGISTRY_ADDRESS=""

if [ -f "solidity/tbtc-stub/deployments/development/Bridge.json" ]; then
  BRIDGE_ADDRESS=$(cat solidity/tbtc-stub/deployments/development/Bridge.json | grep -o '"address": "[^"]*"' | cut -d'"' -f4)
fi

if [ -f "solidity/ecdsa/deployments/development/WalletRegistry.json" ]; then
  WALLET_REGISTRY_ADDRESS=$(cat solidity/ecdsa/deployments/development/WalletRegistry.json | grep -o '"address": "[^"]*"' | cut -d'"' -f4)
fi

if [ -z "$BRIDGE_ADDRESS" ] || [ -z "$WALLET_REGISTRY_ADDRESS" ]; then
  echo -e "${RED}Error: Could not find contract addresses${NC}"
  exit 1
fi

echo "Bridge address: $BRIDGE_ADDRESS"
echo "WalletRegistry address: $WALLET_REGISTRY_ADDRESS"
echo ""

# Check walletOwner
echo "Checking WalletRegistry.walletOwner()..."
WALLET_OWNER=$(cast call "$WALLET_REGISTRY_ADDRESS" "walletOwner()(address)" --rpc-url http://localhost:8545 2>/dev/null || echo "")

if [ -z "$WALLET_OWNER" ]; then
  echo -e "${RED}Error: Could not read walletOwner${NC}"
  exit 1
fi

echo "Current walletOwner: $WALLET_OWNER"
echo "Expected walletOwner: $BRIDGE_ADDRESS"
echo ""

if [ "${WALLET_OWNER,,}" != "${BRIDGE_ADDRESS,,}" ]; then
  echo -e "${RED}✗ MISMATCH: walletOwner is NOT set to Bridge!${NC}"
  echo ""
  echo "To fix this, run:"
  echo "  cd solidity/ecdsa"
  echo "  npx hardhat run scripts/init-wallet-owner.ts --network development"
  echo ""
  exit 1
else
  echo -e "${GREEN}✓ walletOwner is correctly set to Bridge${NC}"
fi

echo ""
echo "Checking DKG state..."
DKG_STATE=$(cast call "$WALLET_REGISTRY_ADDRESS" "getWalletCreationState()(uint8)" --rpc-url http://localhost:8545 2>/dev/null || echo "")
if [ -n "$DKG_STATE" ]; then
  STATE_NAMES=("IDLE" "AWAITING_SEED" "AWAITING_RESULT" "CHALLENGE")
  STATE_NAME=${STATE_NAMES[$DKG_STATE]:-"UNKNOWN"}
  echo "DKG State: $STATE_NAME ($DKG_STATE)"
  
  if [ "$DKG_STATE" != "0" ]; then
    echo -e "${YELLOW}⚠ DKG is not in IDLE state. requestNewWallet() will revert.${NC}"
    echo "Wait for current DKG to complete or timeout."
    exit 1
  else
    echo -e "${GREEN}✓ DKG is in IDLE state${NC}"
  fi
fi

echo ""
echo "=========================================="
echo "Solution: Use Geth Console"
echo "=========================================="
echo ""
echo "The issue is that Bridge.requestNewWallet() forwards to WalletRegistry,"
echo "but the call chain isn't working correctly with cast/Hardhat."
echo ""
echo "Use Geth console directly (this WILL work):"
echo ""
echo -e "${GREEN}geth attach http://localhost:8545${NC}"
echo ""
echo "Then run these commands:"
echo ""
echo "  # Unlock an account"
echo "  personal.unlockAccount(eth.accounts[0], \"\", 0)"
echo ""
echo "  # Send transaction to Bridge"
echo "  eth.sendTransaction({"
echo "    from: eth.accounts[0],"
echo "    to: \"$BRIDGE_ADDRESS\","
echo "    data: \"0x72cc8c6d\","
echo "    gas: 500000"
echo "  })"
echo ""
echo "This will:"
echo "  1. Call Bridge.requestNewWallet()"
echo "  2. Bridge forwards to WalletRegistry.requestNewWallet()"
echo "  3. WalletRegistry sees Bridge as msg.sender (the walletOwner)"
echo "  4. Transaction succeeds!"
echo ""
echo "After sending, check the transaction receipt:"
echo "  ./scripts/check-transaction-receipt.sh <tx-hash>"
echo ""

