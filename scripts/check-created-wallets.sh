#!/bin/bash
# Script to check for created wallets in WalletRegistry
# Checks WalletCreated events and registered wallet status

set -e

cd "$(dirname "$0")/.."

PROJECT_ROOT="$(pwd)"
RPC_URL="${RPC_URL:-http://localhost:8545}"
WR="${WALLET_REGISTRY:-0xd49141e044801DEE237993deDf9684D59fafE2e6}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

echo "=========================================="
echo "Checking Created Wallets"
echo "=========================================="
echo ""
echo "WalletRegistry: $WR"
echo "RPC URL: $RPC_URL"
echo ""

# Get current block number
CURRENT_BLOCK=$(cast block-number --rpc-url "$RPC_URL" 2>/dev/null || echo "unknown")
echo "Current Block: $CURRENT_BLOCK"
echo ""

# Method 1: Check WalletCreated events
log_info "Method 1: Checking WalletCreated events..."

# Query for WalletCreated events from block 0 to latest
WALLET_EVENTS_JSON=$(cast logs --from-block 0 --to-block latest \
  --address "$WR" \
  "WalletCreated(bytes32,bytes32)" \
  --rpc-url "$RPC_URL" \
  --json 2>/dev/null || echo "[]")

WALLET_COUNT=$(echo "$WALLET_EVENTS_JSON" | jq -r 'length' 2>/dev/null || echo "0")

if [ "$WALLET_COUNT" = "0" ] || [ "$WALLET_COUNT" = "null" ]; then
    log_warning "No WalletCreated events found."
    echo ""
    log_info "To create a wallet, run:"
    echo "  ./scripts/request-new-wallet.sh"
    echo ""
else
    log_success "Found $WALLET_COUNT WalletCreated event(s):"
    echo ""
    
    # Process each event
    INDEX=0
    while [ $INDEX -lt "$WALLET_COUNT" ]; do
        event=$(echo "$WALLET_EVENTS_JSON" | jq -c ".[$INDEX]")
        
        # Extract event data
        wallet_id=$(echo "$event" | jq -r '.topics[1]')
        dkg_result_hash=$(echo "$event" | jq -r '.topics[2]')
        block_number_hex=$(echo "$event" | jq -r '.blockNumber')
        block_number=$(printf "%d" "$block_number_hex" 2>/dev/null || echo "$block_number_hex")
        tx_hash=$(echo "$event" | jq -r '.transactionHash')
        
        echo "[$((INDEX + 1))] Wallet:"
        echo "    Wallet ID:      $wallet_id"
        echo "    DKG Result Hash: $dkg_result_hash"
        echo "    Created at Block: $block_number"
        echo "    Transaction:     $tx_hash"
        
        # Method 2: Check if wallet is registered
        IS_REGISTERED=$(cast call "$WR" "isWalletRegistered(bytes32)(bool)" "$wallet_id" --rpc-url "$RPC_URL" 2>/dev/null || echo "false")
        
        if [ "$IS_REGISTERED" = "true" ]; then
            echo "    Status:          ${GREEN}REGISTERED${NC} (Live)"
            
            # Get wallet public key
            PUBLIC_KEY=$(cast call "$WR" "getWalletPublicKey(bytes32)(bytes)" "$wallet_id" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
            if [ -n "$PUBLIC_KEY" ] && [ "$PUBLIC_KEY" != "0x" ]; then
                echo "    Public Key:      ${PUBLIC_KEY:0:20}...${PUBLIC_KEY: -20}"
            fi
            
            # Get wallet info (membersIdsHash, publicKeyX, publicKeyY)
            WALLET_INFO=$(cast call "$WR" "getWallet(bytes32)(bytes32,bytes32,bytes32)" "$wallet_id" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
            if [ -n "$WALLET_INFO" ]; then
                echo "$WALLET_INFO" | head -1 | while IFS= read -r line; do
                    if [ -n "$line" ]; then
                        echo "    Members Hash:   $line"
                    fi
                done
            fi
        else
            echo "    Status:          ${YELLOW}NOT REGISTERED${NC} (Closed or deleted)"
        fi
        
        echo ""
        INDEX=$((INDEX + 1))
    done
fi

# Method 3: Check DKG state
echo "=========================================="
log_info "Method 2: Checking DKG State"
echo "=========================================="

DKG_STATE=$(cast call "$WR" "getWalletCreationState()(uint8)" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
if [ -n "$DKG_STATE" ]; then
    case "$DKG_STATE" in
        0)
            echo "DKG State: ${GREEN}IDLE${NC} (No DKG in progress)"
            ;;
        1)
            echo "DKG State: ${YELLOW}AWAITING_SEED${NC} (Waiting for Random Beacon seed)"
            ;;
        2)
            echo "DKG State: ${YELLOW}AWAITING_RESULT${NC} (DKG protocol in progress)"
            ;;
        3)
            echo "DKG State: ${YELLOW}CHALLENGE${NC} (DKG result submitted, awaiting approval/challenge)"
            ;;
        *)
            echo "DKG State: Unknown ($DKG_STATE)"
            ;;
    esac
else
    log_warning "Could not query DKG state"
fi

echo ""
echo "=========================================="
log_info "Method 3: Using keep-client CLI"
echo "=========================================="
echo ""
echo "You can also check wallets using keep-client:"
echo ""
echo "  # Check DKG state:"
echo "  KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry get-wallet-creation-state --config configs/node1.toml --developer"
echo ""
echo "  # Check if wallet is registered (requires wallet ID):"
echo "  KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry is-wallet-registered <walletID> --config configs/node1.toml --developer"
echo ""
echo "  # Get wallet public key (requires wallet ID):"
echo "  KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry get-wallet-public-key <walletID> --config configs/node1.toml --developer"
echo ""

if [ "$WALLET_COUNT" -gt 0 ]; then
    echo "=========================================="
    log_success "Summary: $WALLET_COUNT wallet(s) found"
    echo "=========================================="
else
    echo "=========================================="
    log_warning "No wallets found"
    echo "=========================================="
fi
