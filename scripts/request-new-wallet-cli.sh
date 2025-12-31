#!/bin/bash
# Script to trigger DKG using keep-client CLI
# This requires Bridge's account keyfile to be available

set -e

cd "$(dirname "$0")/.."

CONFIG="${1:-configs/config.toml}"
BRIDGE_KEYFILE="${2:-}"

echo "=========================================="
echo "Triggering DKG via keep-client CLI"
echo "=========================================="
echo ""
echo "Config: $CONFIG"
echo ""

# Check if Bridge keyfile is provided
if [ -z "$BRIDGE_KEYFILE" ]; then
  echo "⚠️  Bridge keyfile not provided"
  echo ""
  echo "Usage: $0 [config.toml] [bridge_keyfile]"
  echo ""
  echo "The CLI needs Bridge's account keyfile to call requestNewWallet()"
  echo "as the walletOwner."
  echo ""
  echo "Alternative: Use ./scripts/request-new-wallet-geth.sh instead"
  echo "which doesn't require Bridge's keyfile."
  exit 1
fi

if [ ! -f "$BRIDGE_KEYFILE" ]; then
  echo "Error: Bridge keyfile not found: $BRIDGE_KEYFILE"
  exit 1
fi

echo "Bridge keyfile: $BRIDGE_KEYFILE"
echo ""
echo "Calling WalletRegistry.requestNewWallet() via CLI..."
echo ""

# Call WalletRegistry.requestNewWallet() using Bridge's account
keep-client ethereum ecdsa wallet-registry request-new-wallet \
  --config "$CONFIG" \
  --submit \
  --ethereum.keyFile "$BRIDGE_KEYFILE" \
  --ethereum.url http://localhost:8545 \
  --ethereum.password "" 2>&1 || {
  echo ""
  echo "⚠️  CLI call failed. This might be because:"
  echo "   1. Bridge account is not the walletOwner"
  echo "   2. Bridge keyfile password is incorrect"
  echo "   3. Bridge account doesn't have ETH for gas"
  echo ""
  echo "Try using ./scripts/request-new-wallet-geth.sh instead"
  exit 1
}

echo ""
echo "=========================================="
echo "✓ DKG triggered successfully!"
echo "=========================================="
echo ""
echo "Check DKG status with:"
echo "  ./scripts/check-dkg-status.sh"
