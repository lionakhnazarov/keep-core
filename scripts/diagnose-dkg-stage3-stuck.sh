#!/bin/bash
# Script to diagnose why DKG is stuck on Stage 3 (AWAITING_RESULT)

set -e

cd "$(dirname "$0")/.."

RPC_URL="${RPC_URL:-http://localhost:8545}"

echo "=========================================="
echo "DKG Stage 3 (AWAITING_RESULT) Diagnostic"
echo "=========================================="
echo ""

# Check current DKG state
echo "1. Checking DKG State..."
cd solidity/ecdsa
STATE_OUTPUT=$(npx hardhat run scripts/check-dkg-status.ts --network development 2>/dev/null | grep "Wallet Creation State" || echo "")
cd ../..

if [ -n "$STATE_OUTPUT" ]; then
    STATE=$(echo "$STATE_OUTPUT" | grep -oE "\([0-9]+\)" | grep -oE "[0-9]+" || echo "")
    STATE_NAME=$(echo "$STATE_OUTPUT" | grep -oE "(IDLE|AWAITING_SEED|AWAITING_RESULT|CHALLENGE)" | head -1 || echo "")
    echo "   Current State: $STATE_NAME ($STATE)"
    
    if [ "$STATE" != "2" ]; then
        echo "   ⚠️  WARNING: DKG is not in AWAITING_RESULT state!"
        echo "   Expected state: 2 (AWAITING_RESULT), but got: $STATE ($STATE_NAME)"
        echo ""
        echo "   If state is CHALLENGE (3), DKG result was submitted and is being validated."
        echo "   If state is IDLE (0), DKG completed or was reset."
        echo "   If state is AWAITING_SEED (1), waiting for RandomBeacon seed."
    fi
else
    echo "   Could not determine state from script output"
fi

echo ""
echo "2. Checking DKG Timeout Status..."
cd solidity/ecdsa
npx hardhat run scripts/check-dkg-timeout-details.ts --network development 2>/dev/null || echo "   Could not check timeout"
cd ../..

echo ""
echo "3. Checking Recent DKG Events..."
cd solidity/ecdsa
npx hardhat run scripts/check-dkg-status.ts --network development 2>/dev/null | grep -A 20 "Recent DKG Events" || echo "   Could not check events"
cd ../..

echo ""
echo "4. Checking Node Connectivity..."
for i in {1..10}; do
    if [ -f "logs/node${i}.pid" ]; then
        PID=$(cat "logs/node${i}.pid" 2>/dev/null || echo "")
        if [ -n "$PID" ] && ps -p "$PID" > /dev/null 2>&1; then
            METRICS_PORT=$((9600 + i))
            CONNECTED=$(curl -s --max-time 2 "http://localhost:${METRICS_PORT}/metrics" 2>/dev/null | grep -E "^connected_peers_count" | awk '{print $2}' || echo "N/A")
            echo "   Node $i: Running (PID: $PID), Connected Peers: $CONNECTED"
        else
            echo "   Node $i: Not running"
        fi
    fi
done

echo ""
echo "5. Checking DKG Metrics from Nodes..."
for i in {1..10}; do
    if [ -f "logs/node${i}.pid" ]; then
        PID=$(cat "logs/node${i}.pid" 2>/dev/null || echo "")
        if [ -n "$PID" ] && ps -p "$PID" > /dev/null 2>&1; then
            METRICS_PORT=$((9600 + i))
            DKG_JOINED=$(curl -s --max-time 2 "http://localhost:${METRICS_PORT}/metrics" 2>/dev/null | grep -E "^performance_dkg_joined_total" | awk '{print $2}' || echo "0")
            DKG_FAILED=$(curl -s --max-time 2 "http://localhost:${METRICS_PORT}/metrics" 2>/dev/null | grep -E "^performance_dkg_failed_total" | awk '{print $2}' || echo "0")
            if [ "$DKG_JOINED" != "0" ] || [ "$DKG_FAILED" != "0" ]; then
                echo "   Node $i: Joined=$DKG_JOINED, Failed=$DKG_FAILED"
            fi
        fi
    fi
done

echo ""
echo "6. Checking Recent Logs for DKG Activity..."
echo "   Checking last 50 lines of node logs for DKG-related messages..."
for i in {1..10}; do
    if [ -f "logs/node${i}.log" ]; then
        RECENT_DKG=$(tail -50 "logs/node${i}.log" 2>/dev/null | grep -iE "dkg|stage|awaiting|result" | tail -3 || echo "")
        if [ -n "$RECENT_DKG" ]; then
            echo "   Node $i recent DKG activity:"
            echo "$RECENT_DKG" | sed 's/^/      /'
        fi
    fi
done

echo ""
echo "=========================================="
echo "Common Causes for Stage 3 Stuck:"
echo "=========================================="
echo "1. DKG timeout expired - operators didn't submit result in time"
echo "2. Network connectivity issues - operators can't communicate"
echo "3. Operators not participating - nodes not joining DKG"
echo "4. Insufficient operators - not enough operators selected"
echo "5. Block mining stopped - geth not producing blocks"
echo ""
echo "Solutions:"
echo "- Check if DKG timed out: ./scripts/check-dkg-timeout-details.sh"
echo "- Check operator connectivity: Check connected_peers_count metrics"
echo "- Check if operators are in pool: ./scripts/check-operators-in-pool.sh"
echo "- Check block mining: ./scripts/monitor-block-number.sh"
echo "- Reset DKG if timed out: ./scripts/reset-dkg.sh"
echo ""

