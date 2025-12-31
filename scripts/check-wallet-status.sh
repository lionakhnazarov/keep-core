#!/bin/bash
# Script to check wallet status and list created wallets
#
# Usage:
#   ./scripts/check-wallet-status.sh
#
# This script:
#   1. Finds all WalletCreated events from WalletRegistry
#   2. Checks if each wallet is registered
#   3. Displays wallet details including:
#      - Wallet ID
#      - DKG Result Hash
#      - Creation block number
#      - Public key (X and Y coordinates)
#      - Members IDs hash
#
# Alternative ways to check wallets:
#   - Check specific wallet: cast call <WR_ADDRESS> "isWalletRegistered(bytes32)" <WALLET_ID> --rpc-url http://localhost:8545
#   - Get public key: cast call <WR_ADDRESS> "getWalletPublicKey(bytes32)" <WALLET_ID> --rpc-url http://localhost:8545
#   - Get wallet struct: cast call <WR_ADDRESS> "getWallet(bytes32)" <WALLET_ID> --rpc-url http://localhost:8545
#   - List events: cast logs --from-block 0 --to-block latest --address <WR_ADDRESS> "WalletCreated(bytes32,bytes32)" --rpc-url http://localhost:8545

set -e

cd "$(dirname "$0")/.."

PROJECT_ROOT="$(pwd)"
RPC_URL="http://localhost:8545"

# Get WalletRegistry address from deployment
WR=$(jq -r '.address' "$PROJECT_ROOT/solidity/ecdsa/deployments/development/WalletRegistry.json" 2>/dev/null || echo "")

if [ -z "$WR" ] || [ "$WR" = "null" ]; then
  echo "❌ Error: WalletRegistry contract not found"
  echo "   Make sure contracts are deployed: ./scripts/complete-reset.sh"
  exit 1
fi

echo "=========================================="
echo "Wallet Status Check"
echo "=========================================="
echo ""

# Get wallet creation events to find wallet IDs
# Check from block 0 to ensure we find all wallets (or use a reasonable starting point)
FROM_BLOCK=0
# Alternative: Check last 5000 blocks if you want to limit search
# CURRENT_BLOCK=$(cast block-number --rpc-url $RPC_URL | cast --to-dec)
# FROM_BLOCK=$((CURRENT_BLOCK - 5000))

echo "Checking for WalletCreated events..."
echo "WalletRegistry: $WR"
echo ""
WALLET_EVENTS_JSON=$(cast logs --from-block $FROM_BLOCK --to-block latest \
  --address $WR \
  "WalletCreated(bytes32,bytes32)" \
  --rpc-url $RPC_URL \
  --json 2>/dev/null || echo "[]")

if [ -z "$WALLET_EVENTS_JSON" ] || [ "$WALLET_EVENTS_JSON" = "[]" ]; then
  echo "⚠️  No wallets created yet."
  echo ""
  echo "To create a wallet, run:"
  echo "  ./scripts/request-new-wallet.sh"
  exit 0
fi

# Parse JSON output from cast logs
# Each event has topics array with: [event_signature, walletID, dkgResultHash]
WALLET_COUNT=$(echo "$WALLET_EVENTS_JSON" | jq -r 'length' 2>/dev/null || echo "0")

if [ "$WALLET_COUNT" = "0" ] || [ "$WALLET_COUNT" = "null" ]; then
  echo "⚠️  No wallets found in events."
  exit 0
fi

echo "Total wallets found: $WALLET_COUNT"
echo ""

# Process events using array indices
INDEX=0
while [ $INDEX -lt $WALLET_COUNT ]; do
  event=$(echo "$WALLET_EVENTS_JSON" | jq -c ".[$INDEX]")
  wallet_id=$(echo "$event" | jq -r '.topics[1]')
  dkg_result_hash=$(echo "$event" | jq -r '.topics[2]')
  block_number_hex=$(echo "$event" | jq -r '.blockNumber')
  block_number=$(printf "%d" $block_number_hex)
  
  echo "[$INDEX] Wallet ID: $wallet_id"
  echo "    DKG Result Hash: $dkg_result_hash"
  echo "    Created at Block: $block_number"
  
  # Check if wallet is registered
  IS_REGISTERED=$(cast call $WR "isWalletRegistered(bytes32)" $wallet_id --rpc-url $RPC_URL 2>/dev/null || echo "0x0")
  if [ "$IS_REGISTERED" = "0x0000000000000000000000000000000000000000000000000000000000000001" ]; then
    echo "    Status: ✓ Registered"
    
    # Get public key (returns bytes, which may be ABI-encoded)
    # Better to use getWallet struct which returns clean values
    
    # Get wallet struct details (returns 3 bytes32 values: membersIdsHash, publicKeyX, publicKeyY)
    WALLET_DATA=$(cast call $WR "getWallet(bytes32)" $wallet_id --rpc-url $RPC_URL 2>/dev/null || echo "")
    if [ -n "$WALLET_DATA" ] && [ "$WALLET_DATA" != "0x" ] && [ "${#WALLET_DATA}" -gt 2 ]; then
      # Parse struct: 3 bytes32 values = 96 bytes = 192 hex chars + "0x" = 194 chars
      # Each bytes32 is 64 hex chars (32 bytes)
      MEMBERS_HASH="0x$(echo "$WALLET_DATA" | cut -c 3-66)"
      WALLET_X="0x$(echo "$WALLET_DATA" | cut -c 67-130)"
      WALLET_Y="0x$(echo "$WALLET_DATA" | cut -c 131-194)"
      echo "    Members IDs Hash: $MEMBERS_HASH"
      echo "    Public Key X: $WALLET_X"
      echo "    Public Key Y: $WALLET_Y"
    fi
  else
    echo "    Status: ✗ Not Registered (event exists but wallet not in registry)"
  fi
  
  echo ""
  INDEX=$((INDEX + 1))
done

echo "=========================================="
