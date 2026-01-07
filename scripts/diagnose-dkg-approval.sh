#!/bin/bash
# Comprehensive DKG approval diagnosis script

set -eou pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

RPC_URL="http://localhost:8545"
CONFIG_FILE="${1:-configs/node1.toml}"

echo "=========================================="
echo "DKG Approval Diagnosis"
echo "=========================================="
echo ""

# Check DKG state
echo "1. Checking DKG state..."
DKG_STATE=$(KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry get-wallet-creation-state \
  --config "$CONFIG_FILE" --developer 2>&1 | grep -E "^[0-9]+$" | tail -1 || echo "unknown")

echo "   DKG State: $DKG_STATE"
echo "   0 = IDLE, 1 = AWAITING_SEED, 2 = AWAITING_RESULT, 3 = CHALLENGE"
echo ""

if [ "$DKG_STATE" != "3" ]; then
  echo "⚠️  DKG is not in CHALLENGE state. No approval needed."
  exit 0
fi

# Get current block
echo "2. Checking block numbers..."
CURRENT_BLOCK=$(cast block-number --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
echo "   Current Block: $CURRENT_BLOCK"
echo ""

# Check for submission event
echo "3. Checking for DKG result submission event..."
cd solidity/ecdsa
SUBMISSION_INFO=$(npx hardhat run scripts/check-dkg-result-hash.ts --network development 2>&1 | grep -E "(Found DKG result|Submission Block|Event Result Hash|Challenge period|Precedence period)" | head -10 || echo "")

if [ -n "$SUBMISSION_INFO" ]; then
  echo "$SUBMISSION_INFO"
else
  echo "   ⚠️  Could not find submission event"
fi
echo ""

# Check node logs for approval attempts
echo "4. Checking node logs for approval attempts..."
cd "$PROJECT_ROOT"
RECENT_ATTEMPTS=$(grep -E "(failed to approve|cannot approve|approving.*DKG result)" logs/node*.log 2>/dev/null | tail -5 || echo "")
if [ -n "$RECENT_ATTEMPTS" ]; then
  echo "   Recent approval attempts:"
  echo "$RECENT_ATTEMPTS" | sed 's/^/   /'
else
  echo "   No recent approval attempts found"
fi
echo ""

# Check WalletOwner
echo "5. Checking WalletOwner configuration..."
WALLET_OWNER=$(cast call 0xd49141e044801DEE237993deDf9684D59fafE2e6 "walletOwner()(address)" --rpc-url "$RPC_URL" 2>/dev/null || echo "unknown")
echo "   WalletOwner: $WALLET_OWNER"

WALLET_OWNER_CODE=$(cast code "$WALLET_OWNER" --rpc-url "$RPC_URL" 2>/dev/null | head -c 20 || echo "")
if [ "$WALLET_OWNER_CODE" != "0x" ] && [ -n "$WALLET_OWNER_CODE" ]; then
  echo "   ✓ WalletOwner has code deployed"
else
  echo "   ⚠️  WalletOwner has no code"
fi
echo ""

# Summary and recommendations
echo "=========================================="
echo "Summary & Recommendations"
echo "=========================================="
echo ""

if [ "$DKG_STATE" = "3" ]; then
  echo "DKG is in CHALLENGE state and needs approval."
  echo ""
  echo "Recommended actions:"
  echo ""
  echo "1. Try approving using event data (bypasses hash mismatch):"
  echo "   ./scripts/approve-dkg-from-event.sh"
  echo ""
  echo "2. Check hash mismatch:"
  echo "   cd solidity/ecdsa && npx hardhat run scripts/check-dkg-result-hash.ts --network development"
  echo ""
  echo "3. If timing is an issue, mine blocks:"
  echo "   ./scripts/mine-blocks-fast.sh <blocks-needed>"
  echo ""
  echo "4. As last resort, reset DKG:"
  echo "   ./scripts/reset-dkg-from-challenge.sh"
fi

