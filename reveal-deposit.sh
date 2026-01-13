#!/bin/bash
# Reveal deposit using cast (recommended) or keep-client

RPC_URL="http://localhost:8545"

# Get Bridge address from walletOwner (authoritative source)
WR="0xd49141e044801DEE237993deDf9684D59fafE2e6"
BRIDGE=$(cast call "$WR" "walletOwner()(address)" --rpc-url "$RPC_URL" 2>/dev/null | sed 's/0x000000000000000000000000/0x/' || echo "")

# Fallback to deployment files if walletOwner check fails
if [ -z "$BRIDGE" ] || [ "$BRIDGE" = "0x" ] || [ "$BRIDGE" = "0x0000000000000000000000000000000000000000" ]; then
    # Try full Bridge first
    if [ -f "tmp/tbtc-v2/solidity/deployments/development/Bridge.json" ]; then
        BRIDGE=$(jq -r '.address' tmp/tbtc-v2/solidity/deployments/development/Bridge.json 2>/dev/null || echo "")
    fi
    
    # Fallback to Bridge stub
    if [ -z "$BRIDGE" ] || [ "$BRIDGE" = "null" ]; then
        if [ -f "solidity/tbtc-stub/deployments/development/Bridge.json" ]; then
            BRIDGE=$(jq -r '.address' solidity/tbtc-stub/deployments/development/Bridge.json 2>/dev/null || echo "")
        fi
    fi
    
    # Final fallback
    if [ -z "$BRIDGE" ] || [ "$BRIDGE" = "null" ]; then
        BRIDGE="0xc7BC782Da1AAb7ee5985aC94C575f374FA4C75e5"
    fi
fi

# Get first account
ACCOUNT=$(cast rpc eth_accounts --rpc-url "$RPC_URL" 2>/dev/null | jq -r '.[0]' 2>/dev/null || echo "")

if [ -z "$ACCOUNT" ] || [ "$ACCOUNT" = "null" ]; then
  echo "❌ No accounts found. Make sure geth is running."
  exit 1
fi

# Check if deposit data exists
if [ ! -f "deposit-data/funding-tx-info.json" ] || [ ! -f "deposit-data/deposit-reveal-info.json" ]; then
  echo "❌ Deposit data files not found. Run: ./scripts/emulate-deposit.sh"
  exit 1
fi

# Extract values for tuple format
VERSION=$(cat deposit-data/funding-tx-info.json | jq -r '.version')
INPUT_VECTOR=$(cat deposit-data/funding-tx-info.json | jq -r '.inputVector')
OUTPUT_VECTOR=$(cat deposit-data/funding-tx-info.json | jq -r '.outputVector')
LOCKTIME=$(cat deposit-data/funding-tx-info.json | jq -r '.locktime')

FUNDING_OUTPUT_INDEX=$(cat deposit-data/deposit-reveal-info.json | jq -r '.fundingOutputIndex')
BLINDING_FACTOR=$(cat deposit-data/deposit-reveal-info.json | jq -r '.blindingFactor')
WALLET_PKH=$(cat deposit-data/deposit-reveal-info.json | jq -r '.walletPubKeyHash')
REFUND_PKH=$(cat deposit-data/deposit-reveal-info.json | jq -r '.refundPubKeyHash')
REFUND_LOCKTIME=$(cat deposit-data/deposit-reveal-info.json | jq -r '.refundLocktime')
VAULT=$(cat deposit-data/deposit-reveal-info.json | jq -r '.vault')

# Format as tuple
FUNDING_TX_TUPLE="($VERSION,$INPUT_VECTOR,$OUTPUT_VECTOR,$LOCKTIME)"
REVEAL_TUPLE="($FUNDING_OUTPUT_INDEX,$BLINDING_FACTOR,$WALLET_PKH,$REFUND_PKH,$REFUND_LOCKTIME,$VAULT)"

echo "=========================================="
echo "Revealing Deposit"
echo "=========================================="
echo "Bridge: $BRIDGE"
echo "Account: $ACCOUNT"
echo ""

# Submit transaction
cast send "$BRIDGE" \
  "revealDeposit((bytes4,bytes,bytes,bytes4),(uint32,bytes8,bytes20,bytes20,bytes4,address))" \
  "$FUNDING_TX_TUPLE" \
  "$REVEAL_TUPLE" \
  --rpc-url "$RPC_URL" \
  --from "$ACCOUNT" \
  --unlocked
