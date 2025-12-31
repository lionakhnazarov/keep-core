#!/bin/bash
set -eou pipefail

# Script to deploy contracts and update config.toml with new addresses
#
# Usage:
#   ./scripts/deploy-and-update-config.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/configs/config.toml"

echo "=========================================="
echo "Deploy Contracts and Update Config"
echo "=========================================="
echo ""

# Check if Geth is running
if ! curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    http://localhost:8545 > /dev/null 2>&1; then
    echo "❌ Geth is not running!"
    echo ""
    echo "Start Geth first:"
    echo "  ./scripts/start-geth.sh"
    exit 1
fi

echo "✓ Geth is running"
echo ""

# Step 1: Deploy RandomBeacon contracts
echo "=== Step 1: Deploying RandomBeacon Contracts ==="
cd "$PROJECT_ROOT/solidity/random-beacon"
if yarn deploy --network development 2>&1 | tee /tmp/rb-deploy.log; then
    echo "✓ RandomBeacon contracts deployed"
else
    echo "⚠️  RandomBeacon deployment had issues. Check /tmp/rb-deploy.log"
fi
echo ""

# Step 2: Deploy ECDSA contracts
echo "=== Step 2: Deploying ECDSA Contracts ==="
cd "$PROJECT_ROOT/solidity/ecdsa"
if yarn deploy --network development 2>&1 | tee /tmp/ecdsa-deploy.log; then
    echo "✓ ECDSA contracts deployed"
else
    echo "⚠️  ECDSA deployment had issues. Check /tmp/ecdsa-deploy.log"
fi
echo ""

# Step 3: Update config.toml with new addresses
echo "=== Step 3: Updating config.toml ==="

# Get RandomBeacon address
RB_DEPLOYMENT="$PROJECT_ROOT/solidity/random-beacon/deployments/development/RandomBeacon.json"
if [ -f "$RB_DEPLOYMENT" ]; then
    RB_ADDR=$(cat "$RB_DEPLOYMENT" | grep -o '"address":\s*"[^"]*"' | head -1 | cut -d'"' -f4)
    if [ -n "$RB_ADDR" ]; then
        echo "RandomBeacon: $RB_ADDR"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|RandomBeaconAddress = \".*\"|RandomBeaconAddress = \"$RB_ADDR\"|" "$CONFIG_FILE"
        else
            sed -i "s|RandomBeaconAddress = \".*\"|RandomBeaconAddress = \"$RB_ADDR\"|" "$CONFIG_FILE"
        fi
    fi
fi

# Get WalletRegistry address
WR_DEPLOYMENT="$PROJECT_ROOT/solidity/ecdsa/deployments/development/WalletRegistry.json"
if [ -f "$WR_DEPLOYMENT" ]; then
    WR_ADDR=$(cat "$WR_DEPLOYMENT" | grep -o '"address":\s*"[^"]*"' | head -1 | cut -d'"' -f4)
    if [ -n "$WR_ADDR" ]; then
        echo "WalletRegistry: $WR_ADDR"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|WalletRegistryAddress = \".*\"|WalletRegistryAddress = \"$WR_ADDR\"|" "$CONFIG_FILE"
        else
            sed -i "s|WalletRegistryAddress = \".*\"|WalletRegistryAddress = \"$WR_ADDR\"|" "$CONFIG_FILE"
        fi
    fi
fi

echo "✓ Config updated"
echo ""

echo "=========================================="
echo "✓ Deployment Complete!"
echo "=========================================="
echo ""
echo "You can now start nodes:"
echo "  ./configs/start-all-nodes.sh"
echo ""
