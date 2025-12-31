#!/bin/bash
# Script to monitor tBTC deposit and redemption events

set -e

cd "$(dirname "$0")/.."

BRIDGE="0x8aca8D4Ad7b4f2768d1c13018712Da6E3887a79f"
RPC_URL="http://localhost:8545"
FROM_BLOCK=$(cast block-number --rpc-url $RPC_URL | cast --to-dec)
FROM_BLOCK=$((FROM_BLOCK - 100))

echo "=========================================="
echo "tBTC Events Monitor"
echo "=========================================="
echo ""
echo "Bridge: $BRIDGE"
echo "From block: $FROM_BLOCK"
echo ""

# Check for deposit events
echo "=== Deposit Events ==="
DEPOSIT_EVENTS=$(cast logs --from-block $FROM_BLOCK --to-block latest \
  --address $BRIDGE \
  "DepositRevealed(bytes32,bytes32,address,uint256,bytes20,bytes20,uint32,bytes32)" \
  --rpc-url $RPC_URL 2>/dev/null || echo "")

if [ -z "$DEPOSIT_EVENTS" ] || [ "$DEPOSIT_EVENTS" = "[]" ]; then
  echo "  None found"
else
  echo "$DEPOSIT_EVENTS" | jq -r '.'
fi

echo ""

# Check for redemption events
echo "=== Redemption Events ==="
REDEMPTION_EVENTS=$(cast logs --from-block $FROM_BLOCK --to-block latest \
  --address $BRIDGE \
  "RedemptionRequested(bytes32,bytes20,address,bytes,uint64,uint64,uint64)" \
  --rpc-url $RPC_URL 2>/dev/null || echo "")

if [ -z "$REDEMPTION_EVENTS" ] || [ "$REDEMPTION_EVENTS" = "[]" ]; then
  echo "  None found"
else
  echo "$REDEMPTION_EVENTS" | jq -r '.'
fi

echo ""

# Check for wallet creation events from WalletRegistry
echo "=== Wallet Creation Events ==="
WR="0x64F6B5b4AeF3F69952d3B8313F33E99AaAb69241"
WALLET_EVENTS=$(cast logs --from-block $FROM_BLOCK --to-block latest \
  --address $WR \
  "WalletCreated(bytes32,bytes32,bytes32)" \
  --rpc-url $RPC_URL 2>/dev/null || echo "")

if [ -z "$WALLET_EVENTS" ] || [ "$WALLET_EVENTS" = "[]" ]; then
  echo "  None found"
else
  echo "$WALLET_EVENTS" | jq -r '.'
fi

echo ""
echo "=========================================="
echo ""
echo "Note: BridgeStub is a minimal stub and may not emit all events."
echo "For full testing, deploy the complete Bridge contract."
