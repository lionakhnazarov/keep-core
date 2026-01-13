#!/bin/bash
# Check wallet status in both WalletRegistry and Bridge

BRIDGE="0xc7BC782Da1AAb7ee5985aC94C575f374FA4C75e5"
WR="0xd49141e044801DEE237993deDf9684D59fafE2e6"
RPC_URL="http://localhost:8545"
WALLET_ID="0xf90fe699c1ad0877d0df2d35d974e5a2b2c0171041257dc5809b2c2fb3945db9"

echo "=========================================="
echo "Wallet Status Check"
echo "=========================================="
echo ""

# Get wallet public key
WALLET_DATA=$(cast call $WR "getWallet(bytes32)" $WALLET_ID --rpc-url $RPC_URL 2>/dev/null)
PUBKEY_X="0x$(echo "$WALLET_DATA" | cut -c 67-130)"
PUBKEY_Y="0x$(echo "$WALLET_DATA" | cut -c 131-194)"

# Calculate wallet public key hash
COMPRESSED_PUBKEY=$(python3 -c "
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
" 2>/dev/null || echo "")

if [ -z "$COMPRESSED_PUBKEY" ]; then
  # Fallback: use the one from deposit data
  COMPRESSED_PUBKEY=$(cat deposit-data/deposit-data.json 2>/dev/null | jq -r '.walletPublicKeyHash' || echo "")
fi

echo "Wallet ID: $WALLET_ID"
echo "Wallet Public Key Hash: $COMPRESSED_PUBKEY"
echo ""

# Check in WalletRegistry
echo "1. WalletRegistry Status:"
IS_REGISTERED=$(cast call $WR "isWalletRegistered(bytes32)" $WALLET_ID --rpc-url $RPC_URL 2>/dev/null)
if [ "$IS_REGISTERED" = "0x0000000000000000000000000000000000000000000000000000000000000001" ]; then
  echo "   ✅ Registered in WalletRegistry"
else
  echo "   ❌ NOT registered in WalletRegistry"
fi
echo ""

# Check in Bridge
echo "2. Bridge Status:"
WALLET_STATE=$(cast call $BRIDGE "wallets(bytes20)" $COMPRESSED_PUBKEY --rpc-url $RPC_URL 2>/dev/null | cut -c 195-202)
if [ "$WALLET_STATE" = "00000000" ] || [ -z "$WALLET_STATE" ]; then
  echo "   ❌ NOT registered in Bridge (state is Unknown/0)"
  echo ""
  echo "   ⚠️  Issue: Wallet was created before Bridge was deployed"
  echo "   Solution: Create a NEW wallet after Bridge is set as walletOwner"
  echo ""
  echo "   Steps:"
  echo "   1. Set Bridge as walletOwner (requires governance):"
  echo "      cast send $WR \"updateWalletOwner(address)\" $BRIDGE \\"
  echo "        --rpc-url $RPC_URL --unlocked --from <governance>"
  echo ""
  echo "   2. Request a new wallet:"
  echo "      ./scripts/request-new-wallet.sh"
  echo ""
  echo "   3. Wait for DKG to complete and wallet to be created"
  echo ""
  echo "   4. The new wallet will automatically be registered in Bridge"
  echo "      and will be in Live state"
else
  STATE_VALUE=$(printf "%d" 0x$WALLET_STATE 2>/dev/null || echo "0")
  case $STATE_VALUE in
    0) STATE_NAME="Unknown" ;;
    1) STATE_NAME="Live ✅" ;;
    2) STATE_NAME="MovingFunds" ;;
    3) STATE_NAME="Closing" ;;
    4) STATE_NAME="Closed" ;;
    5) STATE_NAME="Terminated" ;;
    *) STATE_NAME="Unknown ($STATE_VALUE)" ;;
  esac
  echo "   ✅ Registered in Bridge - State: $STATE_NAME ($STATE_VALUE)"
fi
echo ""

# Check walletOwner
echo "3. WalletRegistry walletOwner:"
CURRENT_OWNER=$(cast call $WR "walletOwner()" --rpc-url $RPC_URL 2>/dev/null)
echo "   Current: $CURRENT_OWNER"
echo "   Expected: $BRIDGE"
if [ "$CURRENT_OWNER" = "$BRIDGE" ]; then
  echo "   ✅ Bridge is set as walletOwner"
else
  echo "   ❌ Bridge is NOT set as walletOwner"
fi
echo ""
