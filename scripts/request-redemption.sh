#!/bin/bash
# Request a redemption from the Bridge contract
# Usage: ./scripts/request-redemption.sh [options]

set -e

# Default values
RPC_URL="${RPC_URL:-http://localhost:8545}"

# Try to get Bridge address from deployment file, fallback to env var or old default
if [ -z "$BRIDGE_ADDRESS" ]; then
  BRIDGE_DEPLOYMENT_FILE="$(dirname "$0")/../solidity/tbtc-stub/deployments/development/Bridge.json"
  if [ -f "$BRIDGE_DEPLOYMENT_FILE" ]; then
    BRIDGE_ADDRESS=$(jq -r '.address' "$BRIDGE_DEPLOYMENT_FILE" 2>/dev/null || echo "")
  fi
fi
BRIDGE="${BRIDGE_ADDRESS:-0xE050D7EA1Bb14278cBFCa591EaA887e48C9BdE08}"
WALLET_REGISTRY="${WALLET_REGISTRY:-0xd49141e044801DEE237993deDf9684D59fafE2e6}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -w, --wallet HASH      Wallet public key hash (20 bytes, 0x prefixed)"
    echo "  -a, --amount SATS      Amount in satoshis to redeem"
    echo "  -s, --script HEX       Bitcoin redeemer output script (hex)"
    echo "  -k, --private-key KEY  Private key for signing (or use --unlocked)"
    echo "  -u, --unlocked         Use unlocked account (for dev)"
    echo "  -f, --from ADDRESS     From address (with --unlocked)"
    echo "  --list-wallets         List available wallets and exit"
    echo "  --dry-run              Show transaction without sending"
    echo "  -h, --help             Show this help"
    echo ""
    echo "Example:"
    echo "  $0 --wallet 0x... --amount 100000 --script 0x76a914...88ac"
    echo "  $0 --list-wallets"
    echo ""
    echo "Note: Existing wallets may not be registered in the new Bridge."
    echo "      You may need to create a new wallet via DKG first."
}

# Parse arguments
WALLET_PUBKEY_HASH=""
AMOUNT=""
REDEEMER_SCRIPT=""
PRIVATE_KEY=""
UNLOCKED=false
FROM_ADDRESS=""
LIST_WALLETS=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -w|--wallet) WALLET_PUBKEY_HASH="$2"; shift 2 ;;
        -a|--amount) AMOUNT="$2"; shift 2 ;;
        -s|--script) REDEEMER_SCRIPT="$2"; shift 2 ;;
        -k|--private-key) PRIVATE_KEY="$2"; shift 2 ;;
        -u|--unlocked) UNLOCKED=true; shift ;;
        -f|--from) FROM_ADDRESS="$2"; shift 2 ;;
        --list-wallets) LIST_WALLETS=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo "Unknown option: $1"; print_usage; exit 1 ;;
    esac
done

echo -e "${BLUE}=========================================="
echo "tBTC Redemption Request"
echo -e "==========================================${NC}"
echo ""
echo "Bridge: $BRIDGE"
echo "RPC: $RPC_URL"
echo ""

# Function to list wallets registered in Bridge
list_wallets() {
    echo -e "${YELLOW}Checking wallets registered in Bridge...${NC}"
    echo ""
    
    # Known wallet pubkey hashes from node diagnostics
    KNOWN_HASHES=(
        "0x9850b965a0ef404ce03dd88691201cc537beaefd"
        "0x49be77e65eaa59efe636c5757fd3c31fc5efbb66"
        "0xfed577fbba8e72ec01810e12b09d974d7ef6b6bf"
    )
    
    FOUND_REGISTERED=false
    
    for HASH in "${KNOWN_HASHES[@]}"; do
        STATE=$(cast call $BRIDGE "wallets(bytes20)" "$HASH" --rpc-url $RPC_URL 2>/dev/null || echo "error")
        
        if [ "$STATE" = "error" ]; then
            echo "  $HASH: ERROR (could not query)"
        elif [ "$STATE" = "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" ]; then
            echo -e "  $HASH: ${RED}NOT REGISTERED${NC}"
        else
            echo -e "  $HASH: ${GREEN}REGISTERED${NC}"
            FOUND_REGISTERED=true
        fi
    done
    
    echo ""
    
    if [ "$FOUND_REGISTERED" = false ]; then
        echo -e "${YELLOW}No wallets are registered in the new Bridge yet.${NC}"
        echo ""
        echo "To register wallets, you need to create new wallets via DKG:"
        echo "  1. Request new wallet: cast send $BRIDGE \"requestNewWallet(...)\" ..."
        echo "  2. Wait for DKG to complete"
        echo "  3. The new wallet will be automatically registered in Bridge"
        echo ""
        echo "Or manually register existing wallets via governance."
    fi
}

# List wallets if requested
if [ "$LIST_WALLETS" = true ]; then
    list_wallets
    exit 0
fi

# Validate required parameters
if [ -z "$WALLET_PUBKEY_HASH" ]; then
    echo -e "${RED}Error: Wallet public key hash is required${NC}"
    echo "Use --wallet 0x... or --list-wallets to see available wallets"
    exit 1
fi

if [ -z "$AMOUNT" ]; then
    echo -e "${RED}Error: Amount is required${NC}"
    echo "Specify with: --amount <satoshis>"
    exit 1
fi

if [ -z "$REDEEMER_SCRIPT" ]; then
    echo -e "${RED}Error: Redeemer output script is required${NC}"
    echo "Specify with: --script 0x..."
    echo ""
    echo "Script formats:"
    echo "  P2PKH:  0x76a914<20-byte-hash>88ac"
    echo "  P2WPKH: 0x0014<20-byte-hash>"
    echo "  P2SH:   0xa914<20-byte-hash>87"
    exit 1
fi

# Handle signing
if [ -z "$PRIVATE_KEY" ] && [ "$UNLOCKED" = false ]; then
    FROM_ADDRESS=$(cast rpc eth_accounts --rpc-url $RPC_URL 2>/dev/null | jq -r '.[0]')
    UNLOCKED=true
fi

if [ "$UNLOCKED" = true ] && [ -z "$FROM_ADDRESS" ]; then
    FROM_ADDRESS=$(cast rpc eth_accounts --rpc-url $RPC_URL 2>/dev/null | jq -r '.[0]')
fi

echo -e "${GREEN}Redemption Parameters:${NC}"
echo "  Wallet PubKey Hash: $WALLET_PUBKEY_HASH"
echo "  Amount (satoshis):  $AMOUNT"
echo "  Redeemer Script:    $REDEEMER_SCRIPT"
echo "  From:               $FROM_ADDRESS"
echo ""

# Check wallet state in Bridge
echo -e "${YELLOW}Checking wallet state in Bridge...${NC}"
WALLET_STATE=$(cast call $BRIDGE "wallets(bytes20)" "$WALLET_PUBKEY_HASH" --rpc-url $RPC_URL 2>/dev/null || echo "")

# Check if wallet is registered (non-zero state)
if [ -z "$WALLET_STATE" ] || [[ "$WALLET_STATE" =~ ^0x0+$ ]]; then
    echo -e "${RED}Warning: Wallet is NOT registered in Bridge${NC}"
    echo ""
    echo "The wallet must be registered in Bridge before redemption."
    echo "This happens automatically when a new wallet is created via DKG."
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    echo -e "${GREEN}Wallet is registered in Bridge${NC}"
fi

echo ""

# Check if Bridge is the stub (simpler signature) or full Bridge (with mainUtxo)
# Try to detect by checking if the contract has the simpler requestRedemption signature
BRIDGE_IS_STUB=false
if cast call $BRIDGE "requestRedemption(bytes20,bytes,uint64)" "$WALLET_PUBKEY_HASH" "$REDEEMER_SCRIPT" "$AMOUNT" --rpc-url $RPC_URL >/dev/null 2>&1; then
    BRIDGE_IS_STUB=true
fi

if [ "$DRY_RUN" = true ]; then
    echo -e "${BLUE}DRY RUN - Transaction details:${NC}"
    echo ""
    echo "Contract: $BRIDGE"
    if [ "$BRIDGE_IS_STUB" = true ]; then
        echo "Function: requestRedemption(bytes20,bytes,uint64)"
        echo "Args:"
        echo "  walletPubKeyHash: $WALLET_PUBKEY_HASH"
        echo "  redeemerOutputScript: $REDEEMER_SCRIPT"
        echo "  amount: $AMOUNT"
    else
        MAIN_UTXO="(0x0000000000000000000000000000000000000000000000000000000000000000,0,0)"
        echo "Function: requestRedemption(bytes20,(bytes32,uint32,uint64),bytes,uint64)"
        echo "Args:"
        echo "  walletPubKeyHash: $WALLET_PUBKEY_HASH"
        echo "  mainUtxo: $MAIN_UTXO"
        echo "  redeemerOutputScript: $REDEEMER_SCRIPT"
        echo "  amount: $AMOUNT"
    fi
    echo ""
    echo -e "${YELLOW}To execute, remove --dry-run flag${NC}"
    exit 0
fi

echo -e "${GREEN}Sending redemption request...${NC}"
echo ""

# Build and execute cast command
if [ "$BRIDGE_IS_STUB" = true ]; then
    # Bridge stub: requestRedemption(bytes20,bytes,uint64)
    if [ "$UNLOCKED" = true ]; then
        TX_RESULT=$(cast send $BRIDGE \
            "requestRedemption(bytes20,bytes,uint64)" \
            "$WALLET_PUBKEY_HASH" \
            "$REDEEMER_SCRIPT" \
            "$AMOUNT" \
            --rpc-url $RPC_URL \
            --unlocked \
            --from "$FROM_ADDRESS" \
            2>&1) || true
    else
        TX_RESULT=$(cast send $BRIDGE \
            "requestRedemption(bytes20,bytes,uint64)" \
            "$WALLET_PUBKEY_HASH" \
            "$REDEEMER_SCRIPT" \
            "$AMOUNT" \
            --rpc-url $RPC_URL \
            --private-key "$PRIVATE_KEY" \
            2>&1) || true
    fi
else
    # Full Bridge: requestRedemption(bytes20,(bytes32,uint32,uint64),bytes,uint64)
    MAIN_UTXO="(0x0000000000000000000000000000000000000000000000000000000000000000,0,0)"
    if [ "$UNLOCKED" = true ]; then
        TX_RESULT=$(cast send $BRIDGE \
            "requestRedemption(bytes20,(bytes32,uint32,uint64),bytes,uint64)" \
            "$WALLET_PUBKEY_HASH" \
            "$MAIN_UTXO" \
            "$REDEEMER_SCRIPT" \
            "$AMOUNT" \
            --rpc-url $RPC_URL \
            --unlocked \
            --from "$FROM_ADDRESS" \
            2>&1) || true
    else
        TX_RESULT=$(cast send $BRIDGE \
            "requestRedemption(bytes20,(bytes32,uint32,uint64),bytes,uint64)" \
            "$WALLET_PUBKEY_HASH" \
            "$MAIN_UTXO" \
            "$REDEEMER_SCRIPT" \
            "$AMOUNT" \
            --rpc-url $RPC_URL \
            --private-key "$PRIVATE_KEY" \
            2>&1) || true
    fi
fi

if echo "$TX_RESULT" | grep -q "transactionHash"; then
    TX_HASH=$(echo "$TX_RESULT" | grep "transactionHash" | grep -oE '0x[a-fA-F0-9]{64}')
    echo -e "${GREEN}✓ Redemption requested successfully!${NC}"
    echo ""
    echo "Transaction: $TX_HASH"
    echo ""
    
    # Check for events
    echo -e "${YELLOW}Checking for RedemptionRequested event...${NC}"
    sleep 2
    
    cast logs --from-block latest --to-block latest \
        --address $BRIDGE \
        --rpc-url $RPC_URL 2>/dev/null | head -20 || echo "No events found yet"
    
    echo ""
    echo -e "${GREEN}Next: Wait for coordination window for redemption to be processed${NC}"
else
    echo -e "${RED}✗ Transaction failed${NC}"
    echo ""
    echo "$TX_RESULT"
    echo ""
    
    # Common error handling
    if echo "$TX_RESULT" | grep -qi "revert"; then
        echo -e "${YELLOW}Possible causes:${NC}"
        echo "  1. Wallet not registered in Bridge"
        echo "  2. Invalid redeemer output script format"
        echo "  3. Insufficient tBTC balance"
        echo "  4. Wallet not in 'Live' state"
        echo "  5. Invalid main UTXO (needs real UTXO data)"
    fi
    exit 1
fi
