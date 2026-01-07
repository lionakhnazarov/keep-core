#!/bin/bash
# Check WalletRegistry wallet owner and help fix requestNewWallet() errors

set -e

WALLET_REGISTRY=${1:-0xc0a2ee534F004a4ec2EFA541489acBD5ff4bBA99}
RPC_URL=${2:-http://localhost:8545}

echo "=== WalletRegistry Wallet Owner Check ==="
echo "WalletRegistry: $WALLET_REGISTRY"
echo "RPC URL: $RPC_URL"
echo ""

# Check if walletOwner() function exists and get the owner
echo "Checking wallet owner..."
WALLET_OWNER=$(cast call "$WALLET_REGISTRY" \
  "walletOwner()(address)" \
  --rpc-url "$RPC_URL" 2>/dev/null || echo "ERROR")

if [ "$WALLET_OWNER" = "ERROR" ] || [ "$WALLET_OWNER" = "0x0000000000000000000000000000000000000000" ]; then
  echo "⚠️  Could not get wallet owner or wallet owner is not set"
  echo ""
  echo "Possible issues:"
  echo "1. Wallet owner is not initialized"
  echo "2. Contract ABI doesn't match"
  echo ""
  echo "To fix:"
  echo "  cd solidity/ecdsa"
  echo "  npx hardhat run scripts/init-wallet-owner.ts --network development"
  exit 1
fi

echo "Current Wallet Owner: $WALLET_OWNER"
echo ""

# Check what account is being used
CALLER=$(cast rpc eth_accounts --rpc-url "$RPC_URL" | jq -r '.[0]' 2>/dev/null || echo "UNKNOWN")
echo "Your account: ${CALLER:-UNKNOWN}"
echo ""

if [ "$WALLET_OWNER" != "0x0000000000000000000000000000000000000000" ]; then
  if [ "$CALLER" != "UNKNOWN" ] && [ "$(echo "$WALLET_OWNER" | tr '[:upper:]' '[:lower:]')" != "$(echo "$CALLER" | tr '[:upper:]' '[:lower:]')" ]; then
    echo "❌ ERROR: Your account ($CALLER) is NOT the wallet owner!"
    echo "   Wallet owner is: $WALLET_OWNER"
    echo ""
    echo "Solutions:"
    echo ""
    echo "Option 1: Call through Bridge contract (if Bridge is the wallet owner)"
    echo "  cast send $WALLET_OWNER \"requestNewWallet()\" \\"
    echo "    --rpc-url $RPC_URL \\"
    echo "    --unlocked \\"
    echo "    --from $CALLER"
    echo ""
    echo "Option 2: Use the correct account (the wallet owner)"
    echo "  cast send $WALLET_REGISTRY \"requestNewWallet()\" \\"
    echo "    --rpc-url $RPC_URL \\"
    echo "    --unlocked \\"
    echo "    --from $WALLET_OWNER"
    echo ""
    echo "Option 3: Use Keep Client CLI (recommended)"
    echo "  KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry request-new-wallet \\"
    echo "    --submit \\"
    echo "    --config configs/config.toml \\"
    echo "    --developer"
    echo ""
    echo "Option 4: Use Hardhat script"
    echo "  cd solidity/ecdsa"
    echo "  npx hardhat run scripts/request-new-wallet.ts --network development"
    exit 1
  else
    echo "✓ Your account matches the wallet owner"
    echo ""
    echo "You can call requestNewWallet() directly:"
    echo "  cast send $WALLET_REGISTRY \"requestNewWallet()\" \\"
    echo "    --rpc-url $RPC_URL \\"
    echo "    --unlocked \\"
    echo "    --from $CALLER"
  fi
fi

echo ""
echo "=== Additional Checks ==="

# Check DKG state
echo "Checking DKG state..."
DKG_STATE=$(cast call "$WALLET_REGISTRY" \
  "getWalletCreationState()(uint8)" \
  --rpc-url "$RPC_URL" 2>/dev/null || echo "ERROR")

if [ "$DKG_STATE" != "ERROR" ]; then
  case "$DKG_STATE" in
    0) echo "DKG State: IDLE (ready for new wallet)" ;;
    1) echo "DKG State: AWAITING_SEED (waiting for RandomBeacon)" ;;
    2) echo "DKG State: AWAITING_RESULT (DKG in progress)" ;;
    3) echo "DKG State: CHALLENGE (DKG result challenged)" ;;
    *) echo "DKG State: UNKNOWN ($DKG_STATE)" ;;
  esac
  
  if [ "$DKG_STATE" != "0" ]; then
    echo "⚠️  DKG is not in IDLE state. You need to wait for current DKG to complete."
  fi
else
  echo "⚠️  Could not check DKG state"
fi

