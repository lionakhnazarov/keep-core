#!/bin/bash

# Script to advance time on geth node by modifying system time
# This works if geth is running in Docker

set -e

echo "=== Advancing Time on Geth Node ==="

# Check if geth is running in Docker
GETH_CONTAINER=$(docker ps --filter "ancestor=geth-node" --format "{{.ID}}" | head -1)

if [ -z "$GETH_CONTAINER" ]; then
    echo "⚠️  Geth node container not found"
    echo "   Trying to find any geth container..."
    GETH_CONTAINER=$(docker ps --filter "name=geth" --format "{{.ID}}" | head -1)
fi

if [ -z "$GETH_CONTAINER" ]; then
    echo "❌ Could not find geth container"
    echo "   Make sure geth is running in Docker"
    exit 1
fi

echo "Found geth container: $GETH_CONTAINER"

# Get current time from geth
CURRENT_TIME=$(curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest",false],"id":1}' \
  | python3 -c "import sys, json; print(int(json.load(sys.stdin)['result']['timestamp'], 16))")

echo "Current geth timestamp: $CURRENT_TIME"

# Calculate target time (advance by 7 days = 604800 seconds)
TARGET_TIME=$((CURRENT_TIME + 604800 + 1))
echo "Target timestamp: $TARGET_TIME"

# Advance system time in container
echo ""
echo "=== Advancing system time in container ==="
echo "⚠️  This requires Docker to be run with --cap-add SYS_TIME"
echo "   If that's not the case, you'll need to restart geth with that capability"

# Try to set system time
docker exec $GETH_CONTAINER date -s "@$TARGET_TIME" 2>&1 || {
    echo "⚠️  Could not set system time directly"
    echo ""
    echo "Alternative: Use faketime or modify the container's time"
    echo ""
    echo "Option 1: Restart geth with faketime:"
    echo "  docker stop $GETH_CONTAINER"
    echo "  docker run ... --cap-add SYS_TIME ... faketime '7 days' geth ..."
    echo ""
    echo "Option 2: Use debug_setHead to rewind, then initialize wallet owner directly"
    echo ""
    exit 1
}

echo "✓ System time advanced"
echo ""
echo "Now mine a block to update the chain timestamp:"
echo "  curl -X POST http://localhost:8545 -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"miner_start\",\"params\":[1],\"id\":1}'"
echo ""
echo "Then finalize the wallet owner update"
