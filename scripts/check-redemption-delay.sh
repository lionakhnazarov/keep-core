#!/bin/bash
# Script to check current redemption delay values
# Shows both the config-based minimum age and per-request delays

set -eou pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RPC_URL="${RPC_URL:-http://localhost:8545}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Redemption Delay Configuration"
echo "=========================================="
echo ""

# Get WalletProposalValidator address
WALLET_PROPOSAL_VALIDATOR=$(jq -r '.address' "$PROJECT_ROOT/solidity/ecdsa/deployments/development/WalletProposalValidator.json" 2>/dev/null || echo "")

if [ -z "$WALLET_PROPOSAL_VALIDATOR" ] || [ "$WALLET_PROPOSAL_VALIDATOR" = "null" ]; then
    echo -e "${YELLOW}⚠️  WalletProposalValidator not found${NC}"
    echo "   Make sure contracts are deployed"
    exit 1
fi

echo -e "${BLUE}WalletProposalValidator:${NC} $WALLET_PROPOSAL_VALIDATOR"
echo ""

# Get Bridge address to check RedemptionWatchtower
BRIDGE=$(jq -r '.address' "$PROJECT_ROOT/solidity/tbtc-stub/deployments/development/Bridge.json" 2>/dev/null || echo "")

if [ -z "$BRIDGE" ] || [ "$BRIDGE" = "null" ]; then
    echo -e "${YELLOW}⚠️  Bridge not found${NC}"
    echo "   Make sure contracts are deployed"
    exit 1
fi

echo -e "${BLUE}Bridge:${NC} $BRIDGE"
echo ""

# Query REDEMPTION_REQUEST_MIN_AGE from WalletProposalValidator
echo -e "${GREEN}1. Config-Based Minimum Age (REDEMPTION_REQUEST_MIN_AGE)${NC}"
echo "   This is the base minimum age for all redemption requests"
echo ""

MIN_AGE=$(cast call "$WALLET_PROPOSAL_VALIDATOR" \
    "REDEMPTION_REQUEST_MIN_AGE()(uint32)" \
    --rpc-url "$RPC_URL" 2>/dev/null || echo "0")

if [ -z "$MIN_AGE" ] || [ "$MIN_AGE" = "0" ]; then
    echo -e "   ${YELLOW}Value: 0 seconds (no minimum age)${NC}"
else
    MIN_AGE_HOURS=$((MIN_AGE / 3600))
    MIN_AGE_DAYS=$((MIN_AGE / 86400))
    
    if [ $MIN_AGE_DAYS -gt 0 ]; then
        echo -e "   ${GREEN}Value: $MIN_AGE seconds ($MIN_AGE_DAYS days)${NC}"
    elif [ $MIN_AGE_HOURS -gt 0 ]; then
        echo -e "   ${GREEN}Value: $MIN_AGE seconds ($MIN_AGE_HOURS hours)${NC}"
    else
        echo -e "   ${GREEN}Value: $MIN_AGE seconds${NC}"
    fi
fi

echo ""

# Check if RedemptionWatchtower is set
echo -e "${GREEN}2. RedemptionWatchtower (Per-Request Delays)${NC}"
echo "   This allows per-redemption delays (optional)"
echo ""

REDEMPTION_WATCHTOWER=$(cast call "$BRIDGE" \
    "getRedemptionWatchtower()(address)" \
    --rpc-url "$RPC_URL" 2>/dev/null || echo "0x0000000000000000000000000000000000000000")

if [ "$REDEMPTION_WATCHTOWER" = "0x0000000000000000000000000000000000000000" ]; then
    echo -e "   ${YELLOW}Status: Not deployed${NC}"
    echo -e "   ${YELLOW}Address: $REDEMPTION_WATCHTOWER${NC}"
    echo ""
    echo "   Per-request delays are not configured."
    echo "   Only the config-based minimum age applies."
else
    echo -e "   ${GREEN}Status: Deployed${NC}"
    echo -e "   ${GREEN}Address: $REDEMPTION_WATCHTOWER${NC}"
    echo ""
    echo "   Per-request delays can be set via this contract."
    echo "   To check a specific redemption delay, you need:"
    echo "   - Wallet public key hash (20 bytes)"
    echo "   - Redeemer output script"
    echo ""
    echo "   Example query:"
    echo "   cast call $REDEMPTION_WATCHTOWER \\"
    echo "     \"getRedemptionDelay(bytes32)(uint256)\" \\"
    echo "     <redemption_key> \\"
    echo "     --rpc-url $RPC_URL"
fi

echo ""
echo "=========================================="
echo -e "${GREEN}Summary${NC}"
echo "=========================================="
echo ""
echo "Effective delay formula: max(requestMinAge, redemptionDelay)"
echo ""
echo -e "${BLUE}Config-based minimum age:${NC} $MIN_AGE seconds"
if [ "$REDEMPTION_WATCHTOWER" != "0x0000000000000000000000000000000000000000" ]; then
    echo -e "${BLUE}Per-request delays:${NC} Configured (check per redemption)"
else
    echo -e "${BLUE}Per-request delays:${NC} Not configured (defaults to 0)"
fi
echo ""
echo "For most redemptions, the effective delay is: $MIN_AGE seconds"
echo ""

