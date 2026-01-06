#!/bin/bash
# Comprehensive debug script to find why wallet request is reverting

set -e

cd "$(dirname "$0")/.."

BRIDGE_ADDRESS="0xc0a2ee534F004a4ec2EFA541489acBD5ff4bBA99"
WALLET_REGISTRY_ADDRESS="0xd49141e044801DEE237993deDf9684D59fafE2e6"

echo "=========================================="
echo "Debugging Wallet Request Revert"
echo "=========================================="
echo ""

# Check if contracts exist
echo "1. Checking if contracts are deployed..."
BRIDGE_CODE=$(curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getCode\",\"params\":[\"$BRIDGE_ADDRESS\",\"latest\"],\"id\":1}" | \
  jq -r '.result' 2>/dev/null || echo "")

if [ -z "$BRIDGE_CODE" ] || [ "$BRIDGE_CODE" = "0x" ] || [ "$BRIDGE_CODE" = "null" ]; then
  echo "   ✗ Bridge contract not found at $BRIDGE_ADDRESS"
  exit 1
else
  echo "   ✓ Bridge contract exists"
fi

WR_CODE=$(curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getCode\",\"params\":[\"$WALLET_REGISTRY_ADDRESS\",\"latest\"],\"id\":1}" | \
  jq -r '.result' 2>/dev/null || echo "")

if [ -z "$WR_CODE" ] || [ "$WR_CODE" = "0x" ] || [ "$WR_CODE" = "null" ]; then
  echo "   ✗ WalletRegistry contract not found at $WALLET_REGISTRY_ADDRESS"
  exit 1
else
  echo "   ✓ WalletRegistry contract exists"
fi

echo ""
echo "2. Checking walletOwner..."
# Function selector for walletOwner(): 0x893d20e8
WALLET_OWNER_RESULT=$(curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"to\":\"$WALLET_REGISTRY_ADDRESS\",\"data\":\"0x893d20e8\"},\"latest\"],\"id\":1}" | \
  jq -r '.result' 2>/dev/null || echo "")

if [ -n "$WALLET_OWNER_RESULT" ] && [ "$WALLET_OWNER_RESULT" != "null" ] && [ "$WALLET_OWNER_RESULT" != "" ]; then
  WALLET_OWNER="0x${WALLET_OWNER_RESULT: -40}"
  echo "   Current walletOwner: $WALLET_OWNER"
  echo "   Expected walletOwner: $BRIDGE_ADDRESS"
  
  if [ "${WALLET_OWNER,,}" = "${BRIDGE_ADDRESS,,}" ]; then
    echo "   ✓ walletOwner is correctly set"
  else
    echo "   ✗ walletOwner MISMATCH!"
    echo "   Run: cd solidity/ecdsa && npx hardhat run scripts/init-wallet-owner.ts --network development"
    exit 1
  fi
else
  echo "   ⚠ Could not read walletOwner (might be a stub contract)"
fi

echo ""
echo "3. Checking DKG state..."
# Function selector for getWalletCreationState(): 0x5b34b966
DKG_STATE_RESULT=$(curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"to\":\"$WALLET_REGISTRY_ADDRESS\",\"data\":\"0x5b34b966\"},\"latest\"],\"id\":1}" | \
  jq -r '.result' 2>/dev/null || echo "")

if [ -n "$DKG_STATE_RESULT" ] && [ "$DKG_STATE_RESULT" != "null" ] && [ "$DKG_STATE_RESULT" != "" ]; then
  DKG_STATE=$((16#${DKG_STATE_RESULT#0x}))
  STATE_NAMES=("IDLE" "AWAITING_SEED" "AWAITING_RESULT" "CHALLENGE")
  STATE_NAME=${STATE_NAMES[$DKG_STATE]:-"UNKNOWN($DKG_STATE)"}
  echo "   DKG State: $STATE_NAME"
  
  if [ "$DKG_STATE" != "0" ]; then
    echo "   ✗ DKG is NOT in IDLE state!"
    echo "   Wait for DKG to complete or timeout"
    exit 1
  else
    echo "   ✓ DKG is in IDLE state"
  fi
fi

echo ""
echo "4. Testing static call to Bridge.requestNewWallet()..."
# Function selector: 0x72cc8c6d
FIRST_ACCOUNT=$(curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_accounts","params":[],"id":1}' | \
  jq -r '.result[0]' 2>/dev/null || echo "")

if [ -n "$FIRST_ACCOUNT" ]; then
  echo "   Using account: $FIRST_ACCOUNT"
  
  # Try static call
  STATIC_CALL_RESULT=$(curl -s -X POST http://localhost:8545 \
    -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"from\":\"$FIRST_ACCOUNT\",\"to\":\"$BRIDGE_ADDRESS\",\"data\":\"0x72cc8c6d\"},\"latest\"],\"id\":1}" 2>/dev/null)
  
  if echo "$STATIC_CALL_RESULT" | grep -q '"error"'; then
    ERROR_MSG=$(echo "$STATIC_CALL_RESULT" | jq -r '.error.message' 2>/dev/null || echo "Unknown error")
    echo "   ✗ Static call failed: $ERROR_MSG"
    
    # Try to decode revert reason
    ERROR_DATA=$(echo "$STATIC_CALL_RESULT" | jq -r '.error.data' 2>/dev/null || echo "")
    if [ -n "$ERROR_DATA" ] && [ "$ERROR_DATA" != "null" ] && [ "$ERROR_DATA" != "" ]; then
      echo "   Error data: $ERROR_DATA"
      
      # Check for Error(string) selector: 0x08c379a0
      if echo "$ERROR_DATA" | grep -q "08c379a0"; then
        echo "   This is an Error(string) revert"
        # Try to decode (simplified - would need proper ABI decoding)
        echo "   (Use a proper decoder to see the full message)"
      fi
    fi
  else
    echo "   ✓ Static call succeeded (no revert)"
  fi
fi

echo ""
echo "=========================================="
echo "Solution: Use Geth Console"
echo "=========================================="
echo ""
echo "The most reliable method is to use Geth console directly:"
echo ""
echo "  geth attach http://localhost:8545"
echo ""
echo "Then run:"
echo ""
echo "  personal.unlockAccount(eth.accounts[0], \"\", 0)"
echo "  tx = eth.sendTransaction({"
echo "    from: eth.accounts[0],"
echo "    to: \"$BRIDGE_ADDRESS\","
echo "    data: \"0x72cc8c6d\","
echo "    gas: 500000"
echo "  })"
echo "  console.log(\"Transaction hash:\", tx)"
echo ""
echo "After sending, check receipt:"
echo "  ./scripts/check-transaction-receipt.sh <tx-hash>"
echo ""

