#!/bin/bash
# Script to diagnose why DKG approval is failing in CHALLENGE state

set -eou pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

RPC_URL="http://localhost:8545"
CONFIG_FILE="${1:-configs/node1.toml}"

echo "=========================================="
echo "Diagnose DKG Challenge State Issue"
echo "=========================================="
echo ""

# Get current block
CURRENT_BLOCK=$(cast block-number --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
echo "Current block: $CURRENT_BLOCK"
echo ""

# Get DKG state
echo "Checking DKG state..."
DKG_STATE=$(KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry get-wallet-creation-state \
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

STATE_NAME=$(get_state_name "$DKG_STATE")
echo "DKG State: $DKG_STATE ($STATE_NAME)"
echo ""

if [ "$DKG_STATE" != "3" ]; then
    echo "DKG is not in CHALLENGE state. Current state: $STATE_NAME"
    exit 0
fi

# Get WalletRegistry address
WALLET_REGISTRY=$(grep "WalletRegistryAddress" "$CONFIG_FILE" | head -1 | cut -d'"' -f2)
if [ -z "$WALLET_REGISTRY" ]; then
    WALLET_REGISTRY=$(jq -r '.address' solidity/ecdsa/deployments/development/WalletRegistry.json 2>/dev/null || echo "")
fi

if [ -z "$WALLET_REGISTRY" ] || [ "$WALLET_REGISTRY" = "null" ]; then
    echo "Error: Could not find WalletRegistry address"
    exit 1
fi

echo "WalletRegistry: $WALLET_REGISTRY"
echo ""

# Get submission block
echo "Checking submission block..."
SUBMISSION_BLOCK=$(cast call "$WALLET_REGISTRY" "submittedResultBlock()(uint256)" --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
echo "Submission block: $SUBMISSION_BLOCK"
echo ""

# Get challenge period length (from minimum DKG params, should be 10 blocks)
CHALLENGE_PERIOD=10
PRECEDENCE_PERIOD=5

echo "Challenge period: $CHALLENGE_PERIOD blocks"
echo "Precedence period: $PRECEDENCE_PERIOD blocks"
echo ""

# Calculate periods
if [ "$SUBMISSION_BLOCK" != "0" ]; then
    SUBMISSION_DEC=$(printf "%d" "$SUBMISSION_BLOCK" 2>/dev/null || echo "0")
    CURRENT_DEC=$(printf "%d" "$CURRENT_BLOCK" 2>/dev/null || echo "0")
    
    CHALLENGE_END=$((SUBMISSION_DEC + CHALLENGE_PERIOD))
    PRECEDENCE_END=$((CHALLENGE_END + PRECEDENCE_PERIOD))
    
    echo "Challenge period ends at block: $CHALLENGE_END"
    echo "Precedence period ends at block: $PRECEDENCE_END"
    echo ""
    
    if [ "$CURRENT_DEC" -lt "$CHALLENGE_END" ]; then
        BLOCKS_NEEDED=$((CHALLENGE_END - CURRENT_DEC))
        echo "⚠ Challenge period has NOT ended yet"
        echo "   Need $BLOCKS_NEEDED more blocks"
        echo ""
        echo "Mine blocks: ./scripts/mine-blocks-fast.sh $BLOCKS_NEEDED"
    else
        echo "✓ Challenge period has ended"
        echo ""
        
        # Check if nodes are trying to approve
        echo "Checking node logs for approval attempts..."
        APPROVAL_ATTEMPTS=$(grep -E "failed to approve|cannot approve|execution reverted" logs/node*.log 2>/dev/null | wc -l || echo "0")
        echo "Found $APPROVAL_ATTEMPTS approval attempt(s) with errors"
        echo ""
        
        if [ "$APPROVAL_ATTEMPTS" -gt 0 ]; then
            echo "Recent approval errors:"
            grep -E "failed to approve|cannot approve" logs/node*.log 2>/dev/null | tail -3
            echo ""
            echo "Possible causes:"
            echo "  1. Result hash mismatch"
            echo "  2. WalletOwner callback failing"
            echo "  3. Contract validation failing"
            echo ""
            echo "Try manual approval using the approve script:"
            echo "  ./scripts/approve-dkg-result.sh"
        fi
    fi
fi

echo ""
echo "=========================================="
echo "Diagnosis Complete"
echo "=========================================="

