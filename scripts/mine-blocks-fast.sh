#!/bin/bash
# Mine blocks faster to speed up DKG timeout countdown
# This gives the protocol more real-time to complete

set -eou pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

RPC_URL="http://localhost:8545"
BLOCKS_TO_MINE="${1:-10}"
DELAY="${2:-0.1}"  # Delay between blocks (seconds)

echo "Mining $BLOCKS_TO_MINE blocks with ${DELAY}s delay..."
echo "This speeds up block-based timeouts for DKG"
echo ""

START_BLOCK=$(cast block-number --rpc-url "$RPC_URL" 2>/dev/null || echo "0")

for i in $(seq 1 "$BLOCKS_TO_MINE"); do
  cast rpc evm_mine --rpc-url "$RPC_URL" >/dev/null 2>&1 || {
    echo "Failed to mine block $i"
    exit 1
  }
  
  if [ $((i % 10)) -eq 0 ]; then
    CURRENT_BLOCK=$(cast block-number --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
    echo "Mined $i blocks (current: $CURRENT_BLOCK)"
  fi
  
  sleep "$DELAY"
done

END_BLOCK=$(cast block-number --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
MINED=$((END_BLOCK - START_BLOCK))

echo ""
echo "✓ Mined $MINED blocks"
echo "Current block: $END_BLOCK"
