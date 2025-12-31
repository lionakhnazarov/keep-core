#!/bin/bash
# Auto-reset DKG when timed out and immediately retry
# This prevents DKG from getting stuck in AWAITING_RESULT

set -eou pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

CONFIG_FILE="${1:-configs/config.toml}"
RPC_URL="http://localhost:8545"
CHECK_INTERVAL="${2:-5}"  # Check every 5 seconds

echo "=========================================="
echo "Auto-Reset DKG Monitor"
echo "=========================================="
echo "Config: $CONFIG_FILE"
echo "Check interval: ${CHECK_INTERVAL}s"
echo "Press Ctrl+C to stop"
echo ""

while true; do
  STATE=$(KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry get-wallet-creation-state \
    --config "$CONFIG_FILE" --developer 2>&1 | grep -E "^[0-9]+$" | head -1 || echo "")
  
  if [ -z "$STATE" ]; then
    sleep "$CHECK_INTERVAL"
    continue
  fi
  
  if [ "$STATE" = "2" ]; then
    TIMED_OUT=$(KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry has-dkg-timed-out \
      --config "$CONFIG_FILE" --developer 2>&1 | grep -i "true" || echo "")
    
    if [ "$TIMED_OUT" = "true" ]; then
      echo "[$(date +'%Y-%m-%d %H:%M:%S')] ⚠ DKG timed out, resetting..."
      
      WR=$(jq -r '.address' solidity/ecdsa/deployments/development/WalletRegistry.json 2>/dev/null || echo "")
      ACCOUNT=$(cast rpc eth_accounts --rpc-url "$RPC_URL" 2>/dev/null | jq -r '.[0]' || echo "")
      
      if [ -n "$WR" ] && [ -n "$ACCOUNT" ]; then
        TX_HASH=$(cast send "$WR" "notifyDkgTimeout()" \
          --rpc-url "$RPC_URL" \
          --unlocked \
          --from "$ACCOUNT" \
          --gas-limit 300000 2>&1 | grep -oP 'transactionHash: \K[0-9a-fx]+' || echo "")
        
        if [ -n "$TX_HASH" ]; then
          echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✓ Reset transaction: $TX_HASH"
          sleep 3
          
          # Verify reset
          NEW_STATE=$(KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry get-wallet-creation-state \
            --config "$CONFIG_FILE" --developer 2>&1 | grep -E "^[0-9]+$" | head -1 || echo "")
          
          if [ "$NEW_STATE" = "0" ]; then
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✓ DKG reset to IDLE, triggering new DKG..."
            ./scripts/request-new-wallet.sh >/dev/null 2>&1 || true
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✓ New DKG triggered"
          else
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] ⚠ DKG state is: $NEW_STATE (expected 0)"
          fi
        else
          echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✗ Failed to submit reset transaction"
        fi
      else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✗ Could not get WalletRegistry address or account"
      fi
    fi
  fi
  
  sleep "$CHECK_INTERVAL"
done
