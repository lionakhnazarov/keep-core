#!/bin/bash
# Script to emulate tBTC deposit process for development/testing
#
# This script prepares deposit data structures and explains the deposit flow.
# Note: BridgeStub doesn't implement deposit functions, but this shows how
# to prepare the data for when a full Bridge contract is deployed.

set -e

cd "$(dirname "$0")/.."

PROJECT_ROOT="$(pwd)"
RPC_URL="http://localhost:8545"

# Get contract addresses
BRIDGE=$(jq -r '.address' "$PROJECT_ROOT/solidity/tbtc-stub/deployments/development/BridgeStub.json" 2>/dev/null || echo "")
WR=$(jq -r '.address' "$PROJECT_ROOT/solidity/ecdsa/deployments/development/WalletRegistry.json" 2>/dev/null || echo "")

if [ -z "$BRIDGE" ] || [ "$BRIDGE" = "null" ]; then
  echo "❌ Error: Bridge contract not found"
  echo "   Make sure contracts are deployed: ./scripts/complete-reset.sh"
  exit 1
fi

if [ -z "$WR" ] || [ "$WR" = "null" ]; then
  echo "❌ Error: WalletRegistry contract not found"
  exit 1
fi

echo "=========================================="
echo "tBTC Deposit Emulation"
echo "=========================================="
echo ""
echo "Bridge: $BRIDGE"
echo "WalletRegistry: $WR"
echo ""

# Get wallet public key hash
echo "Step 1: Getting wallet public key hash..."
WALLET_EVENTS=$(cast logs --from-block 0 --to-block latest \
  --address $WR \
  "WalletCreated(bytes32,bytes32)" \
  --rpc-url $RPC_URL \
  --json 2>/dev/null || echo "[]")

if [ -z "$WALLET_EVENTS" ] || [ "$WALLET_EVENTS" = "[]" ]; then
  echo "⚠️  No wallets found. Create a wallet first:"
  echo "   ./scripts/request-new-wallet.sh"
  exit 1
fi

# Get the latest wallet's public key (last in the array)
WALLET_COUNT=$(echo "$WALLET_EVENTS" | jq -r 'length' 2>/dev/null || echo "0")
if [ "$WALLET_COUNT" = "0" ]; then
  echo "⚠️  No wallets found. Create a wallet first:"
  echo "   ./scripts/request-new-wallet.sh"
  exit 1
fi
# Get the last wallet (most recently created)
WALLET_INDEX=$((WALLET_COUNT - 1))
WALLET_ID=$(echo "$WALLET_EVENTS" | jq -r ".[$WALLET_INDEX].topics[1]")

echo "  Wallet ID: $WALLET_ID"

# Get wallet struct (returns 3 bytes32 values: membersIdsHash, publicKeyX, publicKeyY)
WALLET_DATA=$(cast call $WR "getWallet(bytes32)" $WALLET_ID --rpc-url $RPC_URL 2>/dev/null || echo "")
if [ -n "$WALLET_DATA" ] && [ "${#WALLET_DATA}" -gt 2 ]; then
  # Parse struct: 3 bytes32 values = 96 bytes = 192 hex chars + "0x" = 194 chars
  PUBKEY_X="0x$(echo "$WALLET_DATA" | cut -c 67-130)"
  PUBKEY_Y="0x$(echo "$WALLET_DATA" | cut -c 131-194)"
  
  echo "  Public Key X: $PUBKEY_X"
  echo "  Public Key Y: $PUBKEY_Y"
  
  # Calculate wallet public key hash (RIPEMD160(SHA256(compressed_pubkey)))
  # Bitcoin uses compressed public keys: 0x02 or 0x03 prefix + X coordinate (32 bytes)
  # Y coordinate determines prefix: 0x02 if Y is even, 0x03 if Y is odd
  PUBKEY_X_CLEAN="${PUBKEY_X#0x}"
  PUBKEY_Y_CLEAN="${PUBKEY_Y#0x}"
  
  # Check if Y is even (last hex digit is 0,2,4,6,8,a,c,e)
  Y_LAST_DIGIT="${PUBKEY_Y_CLEAN:63:1}"
  if [[ "$Y_LAST_DIGIT" =~ [02468ace] ]]; then
    COMPRESSED_PREFIX="02"
  else
    COMPRESSED_PREFIX="03"
  fi
  
  COMPRESSED_PUBKEY="${COMPRESSED_PREFIX}${PUBKEY_X_CLEAN}"
  
  echo "  Public Key (uncompressed): 0x04${PUBKEY_X_CLEAN}${PUBKEY_Y_CLEAN}"
  echo "  Public Key (compressed): 0x${COMPRESSED_PUBKEY}"
  
  # Calculate SHA256 of compressed public key
  COMPRESSED_PUBKEY_BYTES=$(echo -n "$COMPRESSED_PUBKEY" | xxd -r -p)
  PUBKEY_SHA256=$(echo -n "$COMPRESSED_PUBKEY_BYTES" | sha256sum | awk '{print $1}')
  
  # Calculate RIPEMD160 of SHA256 result
  if command -v openssl &> /dev/null; then
    PUBKEY_SHA256_BYTES=$(echo -n "$PUBKEY_SHA256" | xxd -r -p)
    WALLET_PKH=$(echo -n "$PUBKEY_SHA256_BYTES" | openssl dgst -rmd160 -binary | xxd -p -c 20)
    WALLET_PKH="0x$WALLET_PKH"
    echo "  Wallet Public Key Hash: $WALLET_PKH"
  else
    echo "  ⚠️  openssl not found - cannot calculate PKH"
    echo "      Install openssl or use: echo -n <sha256_bytes> | openssl dgst -rmd160"
    WALLET_PKH="0x0000000000000000000000000000000000000000"
  fi
else
  echo "  ⚠️  Could not retrieve wallet public key"
  WALLET_PKH="0x0000000000000000000000000000000000000000"
fi

# Calculate RIPEMD160 (requires openssl or similar)
# Note: This is a simplified example - in production you'd use proper Bitcoin libraries
echo ""
echo "Step 2: Preparing deposit parameters..."
echo ""
echo "⚠️  Note: BridgeStub doesn't implement revealDeposit()"
echo "   This script shows how to prepare deposit data for a full Bridge contract."
echo ""

# Get the account that will call revealDeposit (msg.sender)
# This should be an account with ETH for gas
ACCOUNT=$(cast rpc eth_accounts --rpc-url "$RPC_URL" 2>/dev/null | jq -r '.[0]' 2>/dev/null || echo "")
if [ -z "$ACCOUNT" ] || [ "$ACCOUNT" = "null" ]; then
  echo "⚠️  Warning: No accounts found. Using random depositor."
  DEPOSITOR="${1:-0x$(openssl rand -hex 20)}"
else
  # Use the first account as depositor (msg.sender in revealDeposit)
  DEPOSITOR="${1:-$ACCOUNT}"
fi

AMOUNT="${2:-100000000}"  # 1 BTC in satoshis (default)
BLINDING_FACTOR="0x$(openssl rand -hex 8)"
REFUND_PUBKEY_HASH="0x$(openssl rand -hex 20)"
# Refund locktime must be far enough in the future (at least 24 hours recommended)
# Add 7 days to current timestamp to ensure it's far enough
REFUND_LOCKTIME="0x$(printf '%08x' $(($(date +%s) + 604800)))"

echo "Deposit Parameters:"
echo "  Depositor: $DEPOSITOR"
echo "  Amount: $AMOUNT satoshis ($(echo "scale=8; $AMOUNT / 100000000" | bc) BTC)"
echo "  Blinding Factor: $BLINDING_FACTOR"
echo "  Wallet Public Key Hash: <calculated from wallet>"
echo "  Refund Public Key Hash: $REFUND_PUBKEY_HASH"
echo "  Refund Locktime: $REFUND_LOCKTIME"
echo ""

echo "Step 3: Deposit Flow Explanation"
echo "=========================================="
echo ""
echo "In a real tBTC deposit process:"
echo ""
echo "1. User creates a Bitcoin transaction sending BTC to a deposit script"
echo "   - The script includes: depositor, blinding factor, wallet PKH, refund PKH, locktime"
echo ""
echo "2. User reveals the deposit to Bridge contract using revealDeposit():"
echo "   - Funding transaction info (BitcoinTxInfo)"
echo "   - Deposit reveal info (DepositDepositRevealInfo)"
echo ""
echo "3. Bridge validates and emits DepositRevealed event"
echo ""
echo "4. Wallet operators detect the deposit and create a sweep proposal"
echo ""
echo "5. Operators sign and broadcast sweep transaction to Bitcoin"
echo ""
echo "6. After confirmations, tBTC tokens are minted to depositor"
echo ""

echo "Step 4: Generating Deposit Data Structures"
echo "=========================================="
echo ""

# Create output directory
OUTPUT_DIR="$PROJECT_ROOT/deposit-data"
mkdir -p "$OUTPUT_DIR"

# Generate funding transaction hash (mock)
FUNDING_TX_HASH="0x$(openssl rand -hex 32)"
FUNDING_OUTPUT_INDEX=0

# Create deposit script
# Format: 14<depositor20>7508<blinding8>7576a914<walletPKH20>8763ac6776a914<refundPKH20>8804<locktime4>b175ac68
DEPOSITOR_CLEAN=$(echo "$DEPOSITOR" | sed 's/^0x//')
BLINDING_CLEAN=$(echo "$BLINDING_FACTOR" | sed 's/^0x//')
WALLET_PKH_CLEAN=$(echo "$WALLET_PKH" | sed 's/^0x//')
REFUND_PKH_CLEAN=$(echo "$REFUND_PUBKEY_HASH" | sed 's/^0x//')
REFUND_LOCKTIME_CLEAN=$(echo "$REFUND_LOCKTIME" | sed 's/^0x//')

DEPOSIT_SCRIPT="14${DEPOSITOR_CLEAN}7508${BLINDING_CLEAN}7576a914${WALLET_PKH_CLEAN}8763ac6776a914${REFUND_PKH_CLEAN}8804${REFUND_LOCKTIME_CLEAN}b175ac68"

# Calculate witness script hash (SHA256 of deposit script) for P2WSH output
DEPOSIT_SCRIPT_BYTES=$(echo -n "$DEPOSIT_SCRIPT" | xxd -r -p)
WITNESS_SCRIPT_HASH=$(echo -n "$DEPOSIT_SCRIPT_BYTES" | sha256sum | awk '{print $1}')

# Create mock BitcoinTxInfo
# Note: In real scenario, this would come from actual Bitcoin transaction
# inputVector: compact size (1) + previous tx hash (32) + output index (4) + script (var) + sequence (4)
# For testing, we use a simple input
INPUT_TX_HASH=$(openssl rand -hex 32)
INPUT_OUTPUT_INDEX="00000000"
INPUT_SEQUENCE="ffffffff"
INPUT_SCRIPT_LEN="00"  # Empty script for testing
INPUT_VECTOR="01${INPUT_TX_HASH}${INPUT_OUTPUT_INDEX}${INPUT_SCRIPT_LEN}${INPUT_SEQUENCE}"

# outputVector: compact size (1) + value (8) + script length (1) + P2WSH script (34 bytes: 0x0020<32-byte-hash>)
# Amount in little-endian 8 bytes
AMOUNT_LE=$(printf '%016x' $AMOUNT | sed 's/\(..\)/\1\n/g' | tac | tr -d '\n')
# P2WSH script: 0x0020<32-byte-witness-script-hash> = 34 bytes total
P2WSH_SCRIPT="0020${WITNESS_SCRIPT_HASH}"
P2WSH_SCRIPT_LEN="22"  # 34 bytes = 0x22
OUTPUT_VECTOR="01${AMOUNT_LE}${P2WSH_SCRIPT_LEN}${P2WSH_SCRIPT}"

BITCOIN_TX_INFO=$(cat <<EOF
{
  "version": "0x01000000",
  "inputVector": "0x${INPUT_VECTOR}",
  "outputVector": "0x${OUTPUT_VECTOR}",
  "locktime": "0x00000000"
}
EOF
)

# Create DepositDepositRevealInfo
DEPOSIT_REVEAL_INFO=$(cat <<EOF
{
  "fundingOutputIndex": $FUNDING_OUTPUT_INDEX,
  "blindingFactor": "$BLINDING_FACTOR",
  "walletPubKeyHash": "$WALLET_PKH",
  "refundPubKeyHash": "$REFUND_PUBKEY_HASH",
  "refundLocktime": "$REFUND_LOCKTIME",
  "vault": "0x0000000000000000000000000000000000000000"
}
EOF
)

# Save to files
echo "$BITCOIN_TX_INFO" | jq '.' > "$OUTPUT_DIR/funding-tx-info.json"
echo "$DEPOSIT_REVEAL_INFO" | jq '.' > "$OUTPUT_DIR/deposit-reveal-info.json"

# Create combined deposit data file
DEPOSIT_DATA=$(cat <<EOF
{
  "depositor": "$DEPOSITOR",
  "amount": $AMOUNT,
  "amountBTC": $(echo "scale=8; $AMOUNT / 100000000" | bc),
  "fundingTxHash": "$FUNDING_TX_HASH",
  "fundingOutputIndex": $FUNDING_OUTPUT_INDEX,
  "walletID": "$WALLET_ID",
  "walletPublicKeyHash": "$WALLET_PKH",
  "blindingFactor": "$BLINDING_FACTOR",
  "refundPublicKeyHash": "$REFUND_PUBKEY_HASH",
  "refundLocktime": "$REFUND_LOCKTIME",
  "fundingTxInfo": $BITCOIN_TX_INFO,
  "depositRevealInfo": $DEPOSIT_REVEAL_INFO
}
EOF
)

echo "$DEPOSIT_DATA" | jq '.' > "$OUTPUT_DIR/deposit-data.json"

echo "✅ Deposit data prepared and saved to: $OUTPUT_DIR/"
echo ""
echo "Files created:"
echo "  - deposit-data.json (complete deposit data)"
echo "  - funding-tx-info.json (BitcoinTxInfo structure)"
echo "  - deposit-reveal-info.json (DepositDepositRevealInfo structure)"
echo ""

echo "Deposit Summary:"
echo "  Depositor: $DEPOSITOR"
echo "  Amount: $AMOUNT satoshis ($(echo "scale=8; $AMOUNT / 100000000" | bc) BTC)"
echo "  Funding TX Hash: $FUNDING_TX_HASH"
echo "  Funding Output Index: $FUNDING_OUTPUT_INDEX"
echo "  Wallet PKH: $WALLET_PKH"
echo "  Blinding Factor: $BLINDING_FACTOR"
echo ""

echo "Step 5: Usage Example"
echo "=========================================="
echo ""
echo "To use this deposit data with keep-client (if Bridge supports revealDeposit):"
echo ""
echo "  keep-client bridge reveal-deposit \\"
echo "    --funding-tx-info \"$(cat $OUTPUT_DIR/funding-tx-info.json | jq -c .)\" \\"
echo "    --deposit-reveal-info \"$(cat $OUTPUT_DIR/deposit-reveal-info.json | jq -c .)\""
echo ""
echo "Or using cast (if Bridge contract has revealDeposit function):"
echo ""
echo "  cast send $BRIDGE \"revealDeposit((bytes4,bytes,bytes,bytes4),(uint32,bytes8,bytes20,bytes20,bytes4,address))\" \\"
echo "    \"$(cat $OUTPUT_DIR/funding-tx-info.json | jq -c .)\" \\"
echo "    \"$(cat $OUTPUT_DIR/deposit-reveal-info.json | jq -c .)\" \\"
echo "    --rpc-url $RPC_URL"
echo ""

echo "Step 5: Checking for Deposit Events"
echo "=========================================="
echo ""
FROM_BLOCK=$(cast block-number --rpc-url $RPC_URL | cast --to-dec)
FROM_BLOCK=$((FROM_BLOCK - 1000))

DEPOSIT_EVENTS=$(cast logs --from-block $FROM_BLOCK --to-block latest \
  --address $BRIDGE \
  "DepositRevealed(bytes32,bytes32,address,uint256,bytes20,bytes20,uint32,bytes32)" \
  --rpc-url $RPC_URL \
  --json 2>/dev/null || echo "[]")

DEPOSIT_COUNT=$(echo "$DEPOSIT_EVENTS" | jq -r 'length' 2>/dev/null || echo "0")

if [ "$DEPOSIT_COUNT" = "0" ] || [ "$DEPOSIT_COUNT" = "null" ]; then
  echo "  No deposits found (BridgeStub doesn't emit these events)"
else
  echo "  Found $DEPOSIT_COUNT deposit(s):"
  echo "$DEPOSIT_EVENTS" | jq -r '.'
fi

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
echo "✅ Deposit data successfully prepared for testing!"
echo ""
echo "Generated Files:"
echo "  📄 deposit-data/deposit-data.json"
echo "     Complete deposit information including all parameters"
echo ""
echo "  📄 deposit-data/funding-tx-info.json"
echo "     BitcoinTxInfo structure for revealDeposit() call"
echo ""
echo "  📄 deposit-data/deposit-reveal-info.json"
echo "     DepositDepositRevealInfo structure for revealDeposit() call"
echo ""
echo "Key Values:"
echo "  • Wallet Public Key Hash: $WALLET_PKH"
echo "  • Depositor: $DEPOSITOR"
echo "  • Amount: $AMOUNT satoshis ($(echo "scale=8; $AMOUNT / 100000000" | bc) BTC)"
echo "  • Funding TX Hash: $FUNDING_TX_HASH"
echo ""
echo "Next Steps:"
echo "  1. Review the generated JSON files in deposit-data/"
echo "  2. If BridgeStub is enhanced with revealDeposit(), use the data to call it"
echo "  3. Or deploy the full Bridge contract and use these data structures"
echo "  4. The wallet operators will detect deposits and create sweep proposals"
echo ""
echo "Note: BridgeStub currently doesn't implement revealDeposit()."
echo "      For full testing, deploy the complete Bridge contract."
echo ""
