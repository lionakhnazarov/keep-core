#!/bin/bash
# Script to reset DKG from CHALLENGE state when approval is stuck
# This will reset the DKG state back to IDLE so a new DKG can be started

set -eou pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

RPC_URL="http://localhost:8545"
CONFIG_FILE="${1:-configs/node1.toml}"

echo "=========================================="
echo "Reset DKG from CHALLENGE State"
echo "=========================================="
echo ""
echo "⚠️  WARNING: This will reset the DKG state back to IDLE"
echo "   Any pending DKG result will be lost"
echo ""
read -p "Continue? (y/n): " confirm
if [ "$confirm" != "y" ]; then
    echo "Cancelled"
    exit 0
fi

echo ""
echo "Step 1: Checking current DKG state..."
DKG_STATE=$(KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry get-wallet-creation-state \
  --config "$CONFIG_FILE" --developer 2>&1 | grep -E "^[0-9]+$" | tail -1 || echo "")

if [ "$DKG_STATE" != "3" ]; then
    echo "DKG is not in CHALLENGE state (current: $DKG_STATE)"
    echo "No reset needed"
    exit 0
fi

echo "✓ DKG is in CHALLENGE state"
echo ""

echo "Step 2: Notifying DKG timeout to reset state..."
echo "This will reset DKG back to IDLE state"
echo ""

# Try to notify timeout - this should reset the DKG state
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry notify-dkg-timeout \
  --submit --config "$CONFIG_FILE" --developer 2>&1 | grep -E "(Transaction|hash|Error|error|SUCCESS)" || {
    echo "⚠ notify-dkg-timeout may have failed or already completed"
}

echo ""
echo "Step 3: Verifying DKG state reset..."
sleep 2

NEW_STATE=$(KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry get-wallet-creation-state \
  --config "$CONFIG_FILE" --developer 2>&1 | grep -E "^[0-9]+$" | tail -1 || echo "")

get_state_name() {
    case "$1" in
        0) echo "IDLE" ;;
        1) echo "AWAITING_SEED" ;;
        2) echo "AWAITING_RESULT" ;;
        3) echo "CHALLENGE" ;;
        *) echo "UNKNOWN" ;;
    esac
}

NEW_STATE_NAME=$(get_state_name "$NEW_STATE")
echo "New DKG State: $NEW_STATE ($NEW_STATE_NAME)"
echo ""

if [ "$NEW_STATE" = "0" ]; then
    echo "=========================================="
    echo "✓ SUCCESS! DKG reset to IDLE state"
    echo "=========================================="
    echo ""
    echo "You can now request a new wallet:"
    echo "  ./scripts/request-new-wallet.sh"
    echo ""
else
    echo "=========================================="
    echo "⚠ DKG state is still: $NEW_STATE_NAME"
    echo "=========================================="
    echo ""
    echo "The DKG may need more time or manual intervention."
    echo "You can try:"
    echo "  1. Wait a bit and check again"
    echo "  2. Check node logs for errors"
    echo "  3. Manually reset via Hardhat console"
    echo ""
fi

