#!/bin/bash
# Diagnose why deposit hasn't been swept

RPC_URL="http://localhost:8545"
BRIDGE="0xc7BC782Da1AAb7ee5985aC94C575f374FA4C75e5"

echo "=========================================="
echo "Deposit Sweep Diagnosis"
echo "=========================================="
echo ""

# Get deposit revealed event
echo "1. Extracting deposit details..."
EVENT=$(cast logs --from-block 0 --to-block latest --address $BRIDGE --rpc-url $RPC_URL --json 2>/dev/null | jq -r '.[] | select(.topics[0] == "0xa7382159a693ed317a024daf0fd1ba30805cdf9928ee09550af517c516e2ef05")' | head -1)

if [ -z "$EVENT" ] || [ "$EVENT" == "null" ]; then
  echo "ERROR: No DepositRevealed event found"
  exit 1
fi

# Extract fields
FUNDING_TX_HASH=$(echo "$EVENT" | jq -r '.data[0:66]')
OUTPUT_INDEX_HEX=$(echo "$EVENT" | jq -r '.data[66:130]')
OUTPUT_INDEX=$(printf "%d" 0x${OUTPUT_INDEX_HEX:2})
WALLET_PKH=$(echo "$EVENT" | jq -r '.topics[2]' | sed 's/0x000000000000000000000000//' | sed 's/000000000000000000000000$//')
BLOCK_NUMBER=$(echo "$EVENT" | jq -r '.blockNumber' | xargs printf "%d\n")

echo "Funding TX Hash: $FUNDING_TX_HASH"
echo "Output Index: $OUTPUT_INDEX"
echo "Wallet PKH: $WALLET_PKH"
echo "Revealed at block: $BLOCK_NUMBER"
echo ""

# Check wallet status
echo "2. Checking wallet status in Bridge..."
WALLET_STATUS=$(cast call $BRIDGE "wallets(bytes20)" "$WALLET_PKH" --rpc-url $RPC_URL 2>&1)
if echo "$WALLET_STATUS" | grep -q "execution reverted"; then
  echo "  ERROR: Wallet not found in Bridge"
else
  echo "  Wallet found in Bridge"
  echo "  Status: $WALLET_STATUS"
fi
echo ""

# Check deposit request
echo "3. Checking deposit request..."
DEPOSIT_KEY=$(cast keccak $(cast --concat-hex $FUNDING_TX_HASH $(printf "%064x" $OUTPUT_INDEX)))
DEPOSIT_REQUEST=$(cast call $BRIDGE "deposits(bytes32)" "$DEPOSIT_KEY" --rpc-url $RPC_URL 2>&1)
if echo "$DEPOSIT_REQUEST" | grep -q "execution reverted"; then
  echo "  ERROR: Deposit request not found"
else
  echo "  Deposit request found"
  echo "  Data: $DEPOSIT_REQUEST"
fi
echo ""

# Check Bitcoin confirmations requirement
echo "4. Bitcoin confirmations requirement..."
echo "  Required: 6 confirmations"
echo "  Note: In local dev, the funding TX may not exist on Bitcoin chain"
echo "  This is likely why the deposit hasn't been swept!"
echo ""

# Check which wallets are being coordinated
echo "5. Checking which wallets are being coordinated..."
echo "  Looking for wallet PKH $WALLET_PKH in coordination logs..."
grep -r "walletPKH.*$WALLET_PKH" logs/*.log 2>/dev/null | tail -3 || echo "  No coordination activity found for this wallet"
echo ""

echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
echo "Most likely reason: The funding Bitcoin transaction doesn't exist"
echo "or doesn't have 6 confirmations on the Bitcoin chain."
echo ""
echo "The deposit was revealed on Ethereum, but for it to be swept:"
echo "1. The Bitcoin transaction must exist"
echo "2. It must have at least 6 confirmations"
echo "3. The wallet must be in Live state (checked above)"
echo ""
echo "Since this is a test deposit with mock data, the Bitcoin TX"
echo "likely doesn't exist, preventing the sweep."
