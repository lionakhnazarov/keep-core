#!/bin/bash
set -eou pipefail

# Script to diagnose and fix nodes not running
#
# Usage:
#   ./scripts/fix-nodes-not-running.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=========================================="
echo "Diagnosing Nodes Not Running"
echo "=========================================="
echo ""

# Check 1: Is Geth running?
echo "=== Check 1: Is Geth Running? ==="
if curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    http://localhost:8545 > /dev/null 2>&1; then
    BLOCK_NUM=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        http://localhost:8545 | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
    echo "✓ Geth is running (block: $BLOCK_NUM)"
else
    echo "❌ Geth is NOT running!"
    echo ""
    echo "Start Geth with:"
    echo "  ./scripts/start-geth.sh"
    exit 1
fi
echo ""

# Check 2: Are contracts deployed?
echo "=== Check 2: Are Contracts Deployed? ==="
CONFIG_FILE="$PROJECT_ROOT/configs/config.toml"
RANDOM_BEACON_ADDR=$(grep "RandomBeaconAddress" "$CONFIG_FILE" | grep -o '"[^"]*"' | tr -d '"')
WALLET_REGISTRY_ADDR=$(grep "WalletRegistryAddress" "$CONFIG_FILE" | grep -o '"[^"]*"' | tr -d '"')

if [ -z "$RANDOM_BEACON_ADDR" ] || [ -z "$WALLET_REGISTRY_ADDR" ]; then
    echo "❌ Could not read contract addresses from config"
    exit 1
fi

echo "Checking RandomBeacon at $RANDOM_BEACON_ADDR..."
RB_CODE=$(curl -s -X POST -H "Content-Type: application/json" \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getCode\",\"params\":[\"$RANDOM_BEACON_ADDR\",\"latest\"],\"id\":1}" \
    http://localhost:8545 | grep -o '"result":"[^"]*"' | cut -d'"' -f4)

if [ -z "$RB_CODE" ] || [ "$RB_CODE" = "0x" ] || [ ${#RB_CODE} -le 2 ]; then
    echo "❌ RandomBeacon contract NOT found at $RANDOM_BEACON_ADDR"
    echo ""
    echo "Contracts need to be deployed. Run:"
    echo "  ./scripts/reset-local-setup.sh"
    echo ""
    echo "Or deploy manually:"
    echo "  cd solidity/random-beacon && yarn deploy --network development"
    echo "  cd solidity/ecdsa && yarn deploy --network development"
    exit 1
else
    echo "✓ RandomBeacon contract found"
fi

echo "Checking WalletRegistry at $WALLET_REGISTRY_ADDR..."
WR_CODE=$(curl -s -X POST -H "Content-Type: application/json" \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getCode\",\"params\":[\"$WALLET_REGISTRY_ADDR\",\"latest\"],\"id\":1}" \
    http://localhost:8545 | grep -o '"result":"[^"]*"' | cut -d'"' -f4)

if [ -z "$WR_CODE" ] || [ "$WR_CODE" = "0x" ] || [ ${#WR_CODE} -le 2 ]; then
    echo "❌ WalletRegistry contract NOT found at $WALLET_REGISTRY_ADDR"
    echo ""
    echo "Contracts need to be deployed. Run:"
    echo "  ./scripts/reset-local-setup.sh"
    echo ""
    echo "Or deploy manually:"
    echo "  cd solidity/ecdsa && yarn deploy --network development"
    exit 1
else
    echo "✓ WalletRegistry contract found"
fi
echo ""

# Check 3: Are nodes actually running?
echo "=== Check 3: Node Process Status ==="
if pgrep -f "keep-client.*start" > /dev/null; then
    echo "✓ Keep-client processes are running"
    pgrep -af "keep-client.*start" | head -3
else
    echo "⚠️  No keep-client processes running"
    echo ""
    echo "Start nodes with:"
    echo "  ./configs/start-all-nodes.sh"
fi
echo ""

# Check 4: Check recent logs for errors
echo "=== Check 4: Recent Log Errors ==="
if [ -f "$PROJECT_ROOT/logs/node1.log" ]; then
    ERROR_COUNT=$(tail -50 "$PROJECT_ROOT/logs/node1.log" | grep -i "FATAL\|ERROR" | wc -l | tr -d ' ')
    if [ "$ERROR_COUNT" -gt 0 ]; then
        echo "⚠️  Found $ERROR_COUNT error(s) in node1.log:"
        tail -50 "$PROJECT_ROOT/logs/node1.log" | grep -i "FATAL\|ERROR" | tail -3
    else
        echo "✓ No recent errors in logs"
    fi
else
    echo "⚠️  No log files found"
fi
echo ""

# Summary and recommendations
echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""

if [ -z "$RB_CODE" ] || [ "$RB_CODE" = "0x" ] || [ ${#RB_CODE} -le 2 ]; then
    echo "❌ ISSUE: Contracts are not deployed"
    echo ""
    echo "SOLUTION:"
    echo "  1. Deploy contracts:"
    echo "     ./scripts/reset-local-setup.sh"
    echo ""
    echo "  2. Or deploy manually:"
    echo "     cd solidity/random-beacon"
    echo "     yarn deploy --network development"
    echo "     cd ../ecdsa"
    echo "     yarn deploy --network development"
    echo ""
    echo "  3. Then start nodes:"
    echo "     ./configs/start-all-nodes.sh"
elif ! pgrep -f "keep-client.*start" > /dev/null; then
    echo "✓ Contracts are deployed"
    echo "⚠️  Nodes are not running"
    echo ""
    echo "SOLUTION:"
    echo "  ./configs/start-all-nodes.sh"
else
    echo "✓ Everything looks good!"
    echo ""
    echo "Check node status:"
    echo "  ./configs/check-nodes.sh"
fi
echo ""
