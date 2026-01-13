#!/bin/bash
# Check all wallets and their Bridge status

WR="0xd49141e044801DEE237993deDf9684D59fafE2e6"
RPC_URL="http://localhost:8545"

# Get Bridge address from walletOwner (authoritative source)
BRIDGE=$(cast call "$WR" "walletOwner()(address)" --rpc-url "$RPC_URL" 2>/dev/null | sed 's/0x000000000000000000000000/0x/' || echo "")

# Fallback to Bridge stub if walletOwner check fails
if [ -z "$BRIDGE" ] || [ "$BRIDGE" = "0x" ] || [ "$BRIDGE" = "0x0000000000000000000000000000000000000000" ]; then
    # Try to get from deployment files
    if [ -f "solidity/tbtc-stub/deployments/development/Bridge.json" ]; then
        BRIDGE=$(jq -r '.address' solidity/tbtc-stub/deployments/development/Bridge.json 2>/dev/null || echo "")
    fi
    
    # Fallback to hardcoded Bridge stub
    if [ -z "$BRIDGE" ] || [ "$BRIDGE" = "null" ]; then
        BRIDGE="0xc0a2ee534F004a4ec2EFA541489acBD5ff4bBA99"
    fi
fi

echo "=========================================="
echo "All Wallets Bridge Status Check"
echo "=========================================="
echo ""

# Get all wallets
WALLET_EVENTS=$(cast logs --from-block 0 --to-block latest --address $WR "WalletCreated(bytes32,bytes32)" --rpc-url $RPC_URL --json 2>/dev/null)
WALLET_COUNT=$(echo "$WALLET_EVENTS" | jq -r 'length' 2>/dev/null || echo "0")

echo "Total wallets found: $WALLET_COUNT"
echo ""

if [ "$WALLET_COUNT" = "0" ]; then
  echo "No wallets found"
  exit 0
fi

# Check each wallet
for i in $(seq 0 $((WALLET_COUNT - 1))); do
  WALLET_ID=$(echo "$WALLET_EVENTS" | jq -r ".[$i].topics[1]")
  BLOCK_NUM=$(echo "$WALLET_EVENTS" | jq -r ".[$i].blockNumber" | cast --to-dec 2>/dev/null)
  
  echo "[Wallet $((i+1))]"
  echo "  Wallet ID: $WALLET_ID"
  echo "  Created at Block: $BLOCK_NUM"
  
  # Get wallet data
  WALLET_DATA=$(cast call $WR "getWallet(bytes32)" $WALLET_ID --rpc-url $RPC_URL 2>/dev/null)
  if [ -n "$WALLET_DATA" ] && [ "${#WALLET_DATA}" -gt 2 ]; then
    PUBKEY_X="0x$(echo "$WALLET_DATA" | cut -c 67-130)"
    PUBKEY_Y="0x$(echo "$WALLET_DATA" | cut -c 131-194)"
    
    # Calculate wallet public key hash (simplified - using Python)
    WALLET_PKH=$(python3 << PYTHON_EOF 2>/dev/null
import hashlib
import binascii

pubkey_x = '$PUBKEY_X'
pubkey_y = '$PUBKEY_Y'

# Remove 0x prefix
x_bytes = bytes.fromhex(pubkey_x[2:])
y_bytes = bytes.fromhex(pubkey_y[2:])

# Check if Y is even (last byte is even)
y_int = int(pubkey_y[-2:], 16)
prefix = b'\x02' if y_int % 2 == 0 else b'\x03'

# Compressed public key
compressed = prefix + x_bytes

# SHA256
sha256 = hashlib.sha256(compressed).digest()

# RIPEMD160
ripemd160 = hashlib.new('ripemd160', sha256).digest()

print('0x' + ripemd160.hex())
PYTHON_EOF
)
    
    if [ -n "$WALLET_PKH" ]; then
      echo "  Wallet Public Key Hash: $WALLET_PKH"
      
      # Check Bridge status
      # Wallet struct has 9 fields (each 32 bytes = 64 hex chars):
      # 0: ecdsaWalletID, 1: mainUtxoHash, 2: pendingRedemptionsValue, 3: createdAt,
      # 4: movingFundsRequestedAt, 5: closingStartedAt, 6: pendingMovedFundsSweepRequestsCount,
      # 7: state (enum, last byte at positions 510-511), 8: movingFundsTargetWalletsCommitmentHash
      WALLET_DATA=$(cast call $BRIDGE "wallets(bytes20)" $WALLET_PKH --rpc-url $RPC_URL 2>/dev/null)
      DATA_NO_PREFIX=$(echo "$WALLET_DATA" | sed 's/^0x//')
      # State is at field 7, last byte of that 32-byte slot: positions 510-511 (0-indexed from start of data)
      STATE_HEX="${DATA_NO_PREFIX:510:2}"
      STATE_VALUE=$(printf "%d" 0x$STATE_HEX 2>/dev/null || echo "0")
      
      case $STATE_VALUE in
        0) STATE_NAME="Unknown ❌" ;;
        1) STATE_NAME="Live ✅" ;;
        2) STATE_NAME="MovingFunds" ;;
        3) STATE_NAME="Closing" ;;
        4) STATE_NAME="Closed" ;;
        5) STATE_NAME="Terminated" ;;
        *) STATE_NAME="Unknown ($STATE_VALUE)" ;;
      esac
      
      echo "  Bridge State: $STATE_NAME ($STATE_VALUE)"
      
      if [ "$STATE_VALUE" = "0" ]; then
        echo "  ⚠️  Not registered in Bridge"
      elif [ "$STATE_VALUE" = "1" ]; then
        echo "  ✅ Ready for deposits!"
      fi
    fi
  fi
  echo ""
done

echo "=========================================="
echo "WalletOwner Check"
echo "=========================================="
CURRENT_OWNER=$(cast call $WR "walletOwner()(address)" --rpc-url $RPC_URL 2>/dev/null | sed 's/0x000000000000000000000000/0x/')
echo "Current walletOwner: $CURRENT_OWNER"
echo "Bridge being checked: $BRIDGE"
if [ "$(echo $CURRENT_OWNER | tr '[:upper:]' '[:lower:]')" = "$(echo $BRIDGE | tr '[:upper:]' '[:lower:]')" ]; then
  echo "✅ Bridge is walletOwner"
else
  echo "⚠️  Bridge address differs from walletOwner"
  echo "   (This is OK if walletOwner points to a different Bridge contract)"
  echo ""
  # Check which Bridge type this is
  if [ -f "solidity/tbtc-stub/deployments/development/Bridge.json" ]; then
    BRIDGE_STUB=$(jq -r '.address' solidity/tbtc-stub/deployments/development/Bridge.json 2>/dev/null)
    if [ "$(echo $CURRENT_OWNER | tr '[:upper:]' '[:lower:]')" = "$(echo $BRIDGE_STUB | tr '[:upper:]' '[:lower:]')" ]; then
      echo "   walletOwner is set to Bridge stub"
    fi
  fi
  if [ -f "tmp/tbtc-v2/solidity/deployments/development/Bridge.json" ]; then
    BRIDGE_V2=$(jq -r '.address' tmp/tbtc-v2/solidity/deployments/development/Bridge.json 2>/dev/null)
    if [ "$(echo $CURRENT_OWNER | tr '[:upper:]' '[:lower:]')" = "$(echo $BRIDGE_V2 | tr '[:upper:]' '[:lower:]')" ]; then
      echo "   walletOwner is set to Bridge v2 (full Bridge)"
    fi
  fi
fi
echo ""
