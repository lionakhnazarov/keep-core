#!/bin/bash
# Check deposit sweep events from Bridge contract

RPC_URL="${1:-http://localhost:8545}"
FROM_BLOCK="${2:-0}"
TO_BLOCK="${3:-latest}"

# Get Bridge address from walletOwner (authoritative source)
WR="0xd49141e044801DEE237993deDf9684D59fafE2e6"
BRIDGE=$(cast call "$WR" "walletOwner()(address)" --rpc-url "$RPC_URL" 2>/dev/null | sed 's/0x000000000000000000000000/0x/' || echo "")

# Fallback to deployment files if walletOwner check fails
if [ -z "$BRIDGE" ] || [ "$BRIDGE" = "0x" ] || [ "$BRIDGE" = "0x0000000000000000000000000000000000000000" ]; then
    # Try full Bridge first
    if [ -f "tmp/tbtc-v2/solidity/deployments/development/Bridge.json" ]; then
        BRIDGE=$(jq -r '.address' tmp/tbtc-v2/solidity/deployments/development/Bridge.json 2>/dev/null || echo "")
    fi
    
    # Fallback to Bridge stub
    if [ -z "$BRIDGE" ] || [ "$BRIDGE" = "null" ]; then
        if [ -f "solidity/tbtc-stub/deployments/development/Bridge.json" ]; then
            BRIDGE=$(jq -r '.address' solidity/tbtc-stub/deployments/development/Bridge.json 2>/dev/null || echo "")
        fi
    fi
    
    # Final fallback
    if [ -z "$BRIDGE" ] || [ "$BRIDGE" = "null" ]; then
        echo "Error: Could not find Bridge address"
        exit 1
    fi
fi

echo "=========================================="
echo "Deposit Sweep Events Check"
echo "=========================================="
echo ""
echo "Bridge: $BRIDGE"
echo "RPC URL: $RPC_URL"
echo "Block range: $FROM_BLOCK to $TO_BLOCK"
echo ""

# Check DepositsSwept events
echo "1. DepositsSwept Events"
echo "   (emitted when deposits are swept to wallet)"
echo "   Signature: DepositsSwept(bytes20 walletPubKeyHash, bytes32 sweepTxHash)"
echo ""
DEPOSITS_SWEPT=$(cast logs --from-block "$FROM_BLOCK" --to-block "$TO_BLOCK" \
    --address "$BRIDGE" \
    "DepositsSwept(bytes20,bytes32)" \
    --rpc-url "$RPC_URL" 2>/dev/null || echo "")

if [ -z "$DEPOSITS_SWEPT" ] || [ "$DEPOSITS_SWEPT" = "" ]; then
    echo "   No DepositsSwept events found"
else
    echo "$DEPOSITS_SWEPT" | while IFS= read -r line; do
        if [ -n "$line" ]; then
            echo "   $line"
        fi
    done
fi

echo ""
echo "2. DepositRevealed Events"
echo "   (emitted when deposits are revealed to Bridge)"
echo "   Signature: DepositRevealed(bytes32,uint32,address,uint64,bytes8,bytes20,bytes20,bytes4,address)"
echo ""
DEPOSIT_REVEALED=$(cast logs --from-block "$FROM_BLOCK" --to-block "$TO_BLOCK" \
    --address "$BRIDGE" \
    "DepositRevealed(bytes32,uint32,address,uint64,bytes8,bytes20,bytes20,bytes4,address)" \
    --rpc-url "$RPC_URL" 2>/dev/null || echo "")

if [ -z "$DEPOSIT_REVEALED" ] || [ "$DEPOSIT_REVEALED" = "" ]; then
    echo "   No DepositRevealed events found"
else
    COUNT=$(echo "$DEPOSIT_REVEALED" | grep -c "transactionHash" || echo "0")
    echo "   Found $COUNT DepositRevealed event(s)"
    echo ""
    echo "$DEPOSIT_REVEALED" | grep -E "transactionHash|topics|data" | head -20
fi

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
echo "To monitor deposit sweeps in real-time:"
echo "  watch -n 5 '$0 $RPC_URL'"
echo ""
echo "To check specific wallet:"
echo "  cast logs --address $BRIDGE 'DepositsSwept(bytes20,bytes32)' --rpc-url $RPC_URL | grep <wallet_pkh>"
echo ""
echo "To check node logs for sweep activity:"
echo "  tail -f logs/node*.log | grep -i 'deposit.*sweep\|sweep.*deposit'"
echo ""

