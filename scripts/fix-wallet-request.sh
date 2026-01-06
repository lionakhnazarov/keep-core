#!/bin/bash
# Comprehensive script to diagnose and fix wallet request issues
# This will check everything and provide a working solution

set -e

cd "$(dirname "$0")/.."

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "Comprehensive Wallet Request Diagnostic"
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

# Check walletOwner using direct JSON-RPC
echo "Checking WalletRegistry.walletOwner()..."
WALLET_OWNER_HEX=$(curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"to\":\"$WALLET_REGISTRY_ADDRESS\",\"data\":\"0x893d20e8\"},\"latest\"],\"id\":1}" | \
  jq -r '.result' 2>/dev/null || echo "")

if [ -z "$WALLET_OWNER_HEX" ] || [ "$WALLET_OWNER_HEX" = "null" ] || [ "$WALLET_OWNER_HEX" = "" ]; then
  echo -e "${RED}Error: Could not read walletOwner${NC}"
  echo "Trying alternative method..."
  # Try using cast if available
  if command -v cast >/dev/null 2>&1; then
    WALLET_OWNER=$(cast call "$WALLET_REGISTRY_ADDRESS" "walletOwner()(address)" --rpc-url http://localhost:8545 2>/dev/null || echo "")
  fi
else
  # Convert hex to address (remove 0x prefix and take last 40 chars, add 0x back)
  WALLET_OWNER="0x${WALLET_OWNER_HEX: -40}"
fi

if [ -z "$WALLET_OWNER" ]; then
  echo -e "${YELLOW}⚠ Could not determine walletOwner. Proceeding with assumption that Bridge is correct.${NC}"
  WALLET_OWNER="$BRIDGE_ADDRESS"
else
  echo "Current walletOwner: $WALLET_OWNER"
  echo "Expected walletOwner: $BRIDGE_ADDRESS"
  
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
fi

echo ""
echo "Checking DKG state..."
DKG_STATE_HEX=$(curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"to\":\"$WALLET_REGISTRY_ADDRESS\",\"data\":\"0x5b34b966\"},\"latest\"],\"id\":1}" | \
  jq -r '.result' 2>/dev/null || echo "")

if [ -n "$DKG_STATE_HEX" ] && [ "$DKG_STATE_HEX" != "null" ] && [ "$DKG_STATE_HEX" != "" ]; then
  DKG_STATE=$((16#${DKG_STATE_HEX#0x}))
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
echo "Solution: Direct WalletRegistry Call"
echo "=========================================="
echo ""
echo "The issue is that Bridge.requestNewWallet() forwarding isn't working"
echo "correctly with cast/Hardhat. Let's call WalletRegistry directly as Bridge."
echo ""
echo -e "${BLUE}Method: Use Geth's eth_impersonateAccount${NC}"
echo ""

# Check if Geth supports impersonation
IMPERSONATE_TEST=$(curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_impersonateAccount\",\"params\":[\"$BRIDGE_ADDRESS\"],\"id\":1}" 2>/dev/null | \
  jq -r '.result' 2>/dev/null || echo "")

if [ "$IMPERSONATE_TEST" = "true" ]; then
  echo -e "${GREEN}✓ Geth supports eth_impersonateAccount${NC}"
  echo ""
  echo "Impersonating Bridge and calling WalletRegistry directly..."
  
  # Fund Bridge if needed
  BRIDGE_BALANCE=$(curl -s -X POST http://localhost:8545 \
    -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$BRIDGE_ADDRESS\",\"latest\"],\"id\":1}" | \
    jq -r '.result' | xargs printf "%d")
  
  if [ "$BRIDGE_BALANCE" -lt 100000000000000000 ]; then
    echo "Funding Bridge with ETH..."
    FIRST_ACCOUNT=$(curl -s -X POST http://localhost:8545 \
      -H "Content-Type: application/json" \
      -d '{"jsonrpc":"2.0","method":"eth_accounts","params":[],"id":1}' | \
      jq -r '.result[0]' 2>/dev/null || echo "")
    
    if [ -n "$FIRST_ACCOUNT" ]; then
      curl -s -X POST http://localhost:8545 \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_sendTransaction\",\"params\":[{\"from\":\"$FIRST_ACCOUNT\",\"to\":\"$BRIDGE_ADDRESS\",\"value\":\"0x16345785D8A0000\"}],\"id\":1}" > /dev/null
      echo "✓ Bridge funded"
    fi
  fi
  
  # Now send transaction as Bridge
  echo "Sending transaction as Bridge..."
  TX_HASH=$(curl -s -X POST http://localhost:8545 \
    -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_sendTransaction\",\"params\":[{\"from\":\"$BRIDGE_ADDRESS\",\"to\":\"$WALLET_REGISTRY_ADDRESS\",\"data\":\"0x72cc8c6d\",\"gas\":\"0x7a120\"}],\"id\":1}" | \
    jq -r '.result' 2>/dev/null || echo "")
  
  if [ -n "$TX_HASH" ] && [ "$TX_HASH" != "null" ] && [ "$TX_HASH" != "" ]; then
    echo -e "${GREEN}✓ Transaction sent successfully!${NC}"
    echo "Transaction hash: $TX_HASH"
    echo ""
    echo "Check receipt with:"
    echo "  ./scripts/check-transaction-receipt.sh $TX_HASH"
    
    # Stop impersonation
    curl -s -X POST http://localhost:8545 \
      -H "Content-Type: application/json" \
      -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_stopImpersonatingAccount\",\"params\":[\"$BRIDGE_ADDRESS\"],\"id\":1}" > /dev/null
    
    exit 0
  else
    echo -e "${RED}✗ Transaction failed${NC}"
    curl -s -X POST http://localhost:8545 \
      -H "Content-Type: application/json" \
      -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_stopImpersonatingAccount\",\"params\":[\"$BRIDGE_ADDRESS\"],\"id\":1}" > /dev/null
  fi
else
  echo -e "${YELLOW}⚠ Geth does not support eth_impersonateAccount${NC}"
  echo ""
fi

echo ""
echo "=========================================="
echo "Alternative: Use Geth Console"
echo "=========================================="
echo ""
echo "If impersonation doesn't work, use Geth console:"
echo ""
echo -e "${GREEN}geth attach http://localhost:8545${NC}"
echo ""
echo "Then run:"
echo ""
echo "  # Impersonate Bridge (if supported)"
echo "  eth_impersonateAccount(\"$BRIDGE_ADDRESS\")"
echo ""
echo "  # Fund Bridge if needed"
echo "  eth.sendTransaction({from: eth.accounts[0], to: \"$BRIDGE_ADDRESS\", value: web3.toWei(1, 'ether')})"
echo ""
echo "  # Call WalletRegistry directly as Bridge"
echo "  eth.sendTransaction({"
echo "    from: \"$BRIDGE_ADDRESS\","
echo "    to: \"$WALLET_REGISTRY_ADDRESS\","
echo "    data: \"0x72cc8c6d\","
echo "    gas: 500000"
echo "  })"
echo ""
echo "Or if impersonation doesn't work, try calling Bridge (should forward):"
echo ""
echo "  personal.unlockAccount(eth.accounts[0], \"\", 0)"
echo "  eth.sendTransaction({"
echo "    from: eth.accounts[0],"
echo "    to: \"$BRIDGE_ADDRESS\","
echo "    data: \"0x72cc8c6d\","
echo "    gas: 500000"
echo "  })"
echo ""

