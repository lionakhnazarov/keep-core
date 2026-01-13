#!/bin/bash
# Script to check redemption delay on production (mainnet)
# Queries REDEMPTION_REQUEST_MIN_AGE from WalletProposalValidator

set -eou pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Production RPC endpoints (you can override with RPC_URL env var)
MAINNET_RPC="${RPC_URL:-https://eth.llamarpc.com}"
# Alternative RPC endpoints:
# MAINNET_RPC="https://rpc.ankr.com/eth"
# MAINNET_RPC="https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY"
# MAINNET_RPC="https://mainnet.infura.io/v3/YOUR_PROJECT_ID"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Production Redemption Delay Check"
echo "=========================================="
echo ""
echo -e "${BLUE}RPC Endpoint:${NC} $MAINNET_RPC"
echo ""

# Check if cast is available
if ! command -v cast &> /dev/null; then
    echo -e "${RED}Error: cast (foundry) is not installed${NC}"
    echo "Install it from: https://book.getfoundry.sh/getting-started/installation"
    exit 1
fi

# WalletProposalValidator address on mainnet
# NOTE: You need to find the actual production address
# This is a placeholder - replace with actual address
WALLET_PROPOSAL_VALIDATOR="${WALLET_PROPOSAL_VALIDATOR:-}"

if [ -z "$WALLET_PROPOSAL_VALIDATOR" ]; then
    echo -e "${YELLOW}⚠️  WalletProposalValidator address not set${NC}"
    echo ""
    echo "Please set the WALLET_PROPOSAL_VALIDATOR environment variable:"
    echo "  export WALLET_PROPOSAL_VALIDATOR=0x..."
    echo ""
    echo "Or find it from:"
    echo "  1. Bridge contract: Bridge.getWalletProposalValidator()"
    echo "  2. tBTC documentation"
    echo "  3. Etherscan (search for WalletProposalValidator)"
    echo ""
    echo "Example:"
    echo "  export WALLET_PROPOSAL_VALIDATOR=0x1234567890123456789012345678901234567890"
    echo "  $0"
    exit 1
fi

echo -e "${BLUE}WalletProposalValidator:${NC} $WALLET_PROPOSAL_VALIDATOR"
echo ""

# Query REDEMPTION_REQUEST_MIN_AGE
echo -e "${GREEN}Querying REDEMPTION_REQUEST_MIN_AGE...${NC}"
echo ""

MIN_AGE=$(cast call "$WALLET_PROPOSAL_VALIDATOR" \
    "REDEMPTION_REQUEST_MIN_AGE()(uint32)" \
    --rpc-url "$MAINNET_RPC" 2>&1)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error querying contract:${NC}"
    echo "$MIN_AGE"
    echo ""
    echo "Possible issues:"
    echo "  - Wrong contract address"
    echo "  - RPC endpoint not accessible"
    echo "  - Contract not deployed at this address"
    exit 1
fi

# Parse and display result
if [ -z "$MIN_AGE" ] || [ "$MIN_AGE" = "0" ]; then
    echo -e "   ${YELLOW}Value: 0 seconds (no minimum age)${NC}"
    echo ""
    echo "   This means redemption requests can be processed immediately"
    echo "   (subject to coordination windows and other delays)"
else
    MIN_AGE_HOURS=$((MIN_AGE / 3600))
    MIN_AGE_DAYS=$((MIN_AGE / 86400))
    MIN_AGE_WEEKS=$((MIN_AGE / 604800))
    
    echo -e "   ${GREEN}Value: $MIN_AGE seconds${NC}"
    echo ""
    
    if [ $MIN_AGE_WEEKS -gt 0 ]; then
        echo -e "   ${GREEN}Equivalent: $MIN_AGE_WEEKS week(s)${NC}"
    elif [ $MIN_AGE_DAYS -gt 0 ]; then
        echo -e "   ${GREEN}Equivalent: $MIN_AGE_DAYS day(s)${NC}"
    elif [ $MIN_AGE_HOURS -gt 0 ]; then
        echo -e "   ${GREEN}Equivalent: $MIN_AGE_HOURS hour(s)${NC}"
    fi
    
    echo ""
    echo "   Redemption requests must wait this long before being processed"
fi

echo ""
echo "=========================================="
echo -e "${GREEN}Additional Information${NC}"
echo "=========================================="
echo ""

# Check RedemptionWatchtower (optional)
BRIDGE="${BRIDGE:-}"

if [ -n "$BRIDGE" ] && [ "$BRIDGE" != "" ]; then
    echo -e "${BLUE}Checking RedemptionWatchtower...${NC}"
    echo ""
    
    REDEMPTION_WATCHTOWER=$(cast call "$BRIDGE" \
        "getRedemptionWatchtower()(address)" \
        --rpc-url "$MAINNET_RPC" 2>/dev/null || echo "0x0000000000000000000000000000000000000000")
    
    if [ "$REDEMPTION_WATCHTOWER" = "0x0000000000000000000000000000000000000000" ]; then
        echo -e "   ${YELLOW}RedemptionWatchtower: Not deployed${NC}"
        echo "   Per-request delays are not configured"
    else
        echo -e "   ${GREEN}RedemptionWatchtower: $REDEMPTION_WATCHTOWER${NC}"
        echo "   Per-request delays may be configured"
        echo ""
        echo "   To check a specific redemption delay:"
        echo "   cast call $REDEMPTION_WATCHTOWER \\"
        echo "     \"getRedemptionDelay(bytes32)(uint256)\" \\"
        echo "     <redemption_key> \\"
        echo "     --rpc-url $MAINNET_RPC"
    fi
    echo ""
fi

echo "Effective delay formula: max(requestMinAge, redemptionDelay)"
echo ""
echo -e "${BLUE}Config-based minimum age:${NC} $MIN_AGE seconds"
if [ "$MIN_AGE" != "0" ]; then
    echo "   This is the minimum wait time for all redemption requests"
fi
echo ""

echo "To check on Etherscan:"
echo "  https://etherscan.io/address/$WALLET_PROPOSAL_VALIDATOR#readContract"
echo "  Look for: REDEMPTION_REQUEST_MIN_AGE"
echo ""

