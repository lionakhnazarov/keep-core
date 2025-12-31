#!/bin/bash
# Script to speed up DKG processing without increasing timeout
# Solutions: Speed up block mining, optimize protocol, monitor closely

set -eou pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

RPC_URL="http://localhost:8545"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "Speed Up DKG Processing (Without Increasing Timeout)"
echo "=========================================="
echo ""

# Solution 1: Speed up block mining
echo -e "${BLUE}Solution 1: Speed Up Block Mining${NC}"
echo ""
echo "The DKG timeout is measured in blocks. If blocks are mined faster,"
echo "the protocol has more real-time to complete."
echo ""

# Check current block time
echo "Checking current block mining rate..."
CURRENT_BLOCK=$(cast block-number --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
sleep 2
NEW_BLOCK=$(cast block-number --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
BLOCK_TIME=$((NEW_BLOCK - CURRENT_BLOCK))

if [ "$BLOCK_TIME" -gt 0 ]; then
    echo "Current block rate: ~$BLOCK_TIME blocks per 2 seconds"
    echo ""
    echo -e "${YELLOW}To speed up mining, restart Geth with faster mining:${NC}"
    echo ""
    echo "1. Stop Geth container:"
    echo "   docker-compose -f infrastructure/docker-compose.yml stop geth-node"
    echo ""
    echo "2. Modify docker-entrypoint.sh to add:"
    echo "   --miner.gastarget=8000000 \\"
    echo "   --miner.gaslimit=8000000 \\"
    echo ""
    echo "3. Or use dev mode with instant mining:"
    echo "   Add to geth command: --dev --dev.period=1"
    echo ""
else
    echo "Could not determine block rate"
fi
echo ""

# Solution 2: Monitor and auto-reset if timeout
echo -e "${BLUE}Solution 2: Auto-Reset on Timeout${NC}"
echo ""
echo "Create a monitoring loop that resets DKG immediately when it times out:"
echo ""
cat <<'MONITOR_SCRIPT'
#!/bin/bash
# Auto-reset DKG when timed out
CONFIG_FILE="${1:-configs/config.toml}"

while true; do
  STATE=$(KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry get-wallet-creation-state \
    --config "$CONFIG_FILE" --developer 2>&1 | grep -E "^[0-9]+$" | head -1)
  
  if [ "$STATE" = "2" ]; then
    TIMED_OUT=$(KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry has-dkg-timed-out \
      --config "$CONFIG_FILE" --developer 2>&1 | grep -i "true" || echo "")
    
    if [ "$TIMED_OUT" = "true" ]; then
      echo "[$(date)] DKG timed out, resetting..."
      WR=$(jq -r '.address' solidity/ecdsa/deployments/development/WalletRegistry.json)
      ACCOUNT=$(cast rpc eth_accounts --rpc-url http://localhost:8545 | jq -r '.[0]')
      cast send "$WR" "notifyDkgTimeout()" --rpc-url http://localhost:8545 --unlocked --from "$ACCOUNT" --gas-limit 300000 >/dev/null 2>&1
      sleep 2
      echo "[$(date)] DKG reset, triggering new DKG..."
      ./scripts/request-new-wallet.sh >/dev/null 2>&1
    fi
  fi
  
  sleep 5
done
MONITOR_SCRIPT

echo ""
echo "Save this as: scripts/auto-reset-dkg.sh"
echo "Run: ./scripts/auto-reset-dkg.sh configs/config.toml"
echo ""

# Solution 3: Optimize protocol by ensuring all nodes are ready
echo -e "${BLUE}Solution 3: Ensure All Nodes Are Ready${NC}"
echo ""
echo "DKG protocol speed depends on network communication between nodes."
echo "Ensure optimal conditions:"
echo ""
echo "1. Check all nodes are running:"
echo "   ps aux | grep 'keep-client.*start' | wc -l"
echo ""
echo "2. Check libp2p connectivity:"
echo "   tail -f logs/node*.log | grep -i 'peer\|connection\|network'"
echo ""
echo "3. Ensure nodes are on same network:"
echo "   # Check configs/config.toml and configs/node*.toml"
echo "   # Ensure libp2p addresses are accessible"
echo ""
echo "4. Reduce network latency:"
echo "   # Run all nodes on same machine or low-latency network"
echo ""

# Solution 4: Trigger DKG immediately after reset
echo -e "${BLUE}Solution 4: Immediate Re-trigger After Reset${NC}"
echo ""
echo "Create a script that resets and immediately triggers new DKG:"
echo ""
cat <<'RESET_AND_RETRY'
#!/bin/bash
# Reset timed-out DKG and immediately trigger new one
WR=$(jq -r '.address' solidity/ecdsa/deployments/development/WalletRegistry.json)
ACCOUNT=$(cast rpc eth_accounts --rpc-url http://localhost:8545 | jq -r '.[0]')

echo "Resetting DKG..."
cast send "$WR" "notifyDkgTimeout()" --rpc-url http://localhost:8545 --unlocked --from "$ACCOUNT" --gas-limit 300000 >/dev/null 2>&1
sleep 2

echo "Triggering new DKG..."
./scripts/request-new-wallet.sh

echo "Monitoring DKG progress..."
tail -f logs/node*.log | grep -i "dkg\|phase\|submitting\|result"
RESET_AND_RETRY

echo ""
echo "Save this as: scripts/reset-and-retry-dkg.sh"
echo ""

# Solution 5: Check protocol completion speed
echo -e "${BLUE}Solution 5: Monitor Protocol Speed${NC}"
echo ""
echo "Track how long each phase takes:"
echo ""
cat <<'SPEED_MONITOR'
#!/bin/bash
# Monitor DKG protocol speed
echo "Monitoring DKG protocol phases..."
tail -f logs/node*.log | grep -E "starting.*phase|phase.*complete|submitting.*result|DKG.*complete" | while read line; do
  echo "[$(date +%H:%M:%S)] $line"
done
SPEED_MONITOR

echo ""
echo "Save this as: scripts/monitor-dkg-speed.sh"
echo ""

# Solution 6: Manual block mining acceleration
echo -e "${BLUE}Solution 6: Manual Block Mining Acceleration${NC}"
echo ""
echo "If using Geth, you can manually mine blocks faster:"
echo ""
echo "1. Connect to Geth console:"
echo "   cast rpc --rpc-url http://localhost:8545"
echo ""
echo "2. Mine blocks manually:"
echo "   cast rpc miner_start --rpc-url http://localhost:8545"
echo "   # Or mine specific number of blocks"
echo ""
echo "3. Or use cast to mine blocks:"
cat <<'MINE_BLOCKS'
#!/bin/bash
# Mine blocks faster during DKG
RPC_URL="http://localhost:8545"

echo "Mining blocks to speed up DKG..."
for i in {1..50}; do
  cast rpc evm_mine --rpc-url "$RPC_URL" >/dev/null 2>&1
  sleep 0.1
done
echo "Mined 50 blocks"
MINE_BLOCKS

echo ""
echo "Save this as: scripts/mine-blocks.sh"
echo ""

# Summary
echo "=========================================="
echo "Summary: Best Approaches"
echo "=========================================="
echo ""
echo "1. ${GREEN}Speed up block mining${NC} (most effective)"
echo "   - Modify Geth to mine faster (--dev.period=1)"
echo "   - Or manually mine blocks during DKG"
echo ""
echo "2. ${GREEN}Auto-reset on timeout${NC} (prevents stuck state)"
echo "   - Run auto-reset-dkg.sh in background"
echo "   - Automatically retries when timeout occurs"
echo ""
echo "3. ${GREEN}Optimize network${NC} (reduces protocol time)"
echo "   - Ensure all nodes can communicate quickly"
echo "   - Run on same machine or low-latency network"
echo ""
echo "4. ${GREEN}Monitor closely${NC} (catch issues early)"
echo "   - Use monitor-dkg-speed.sh to track progress"
echo "   - Reset immediately if timeout detected"
echo ""
echo "Recommended: Combine solutions 1 + 2"
echo "  - Speed up mining AND auto-reset on timeout"
echo ""
