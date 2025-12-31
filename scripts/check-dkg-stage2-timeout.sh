#!/bin/bash
# Script to calculate when DKG Stage 2 (AWAITING_RESULT) will timeout

set -e

cd "$(dirname "$0")/.."
PROJECT_ROOT="$PWD"

# Get WalletRegistry address from deployment file
WR_DEPLOYMENT="$PROJECT_ROOT/solidity/ecdsa/deployments/development/WalletRegistry.json"
if [ -f "$WR_DEPLOYMENT" ]; then
  WR=$(jq -r '.address' "$WR_DEPLOYMENT")
else
  # Fallback to known address
  WR="0xe83f7D612f660c873e99f71Dd558E5489ECead50"
fi
RPC_URL="http://localhost:8545"

echo "=========================================="
echo "DKG Stage 2 (AWAITING_RESULT) Timeout"
echo "=========================================="
echo ""

# Get current state
STATE=$(cast call $WR "getWalletCreationState()" --rpc-url $RPC_URL | cast --to-dec)
echo "Current DKG State: $STATE"
echo "  (0=IDLE, 1=AWAITING_SEED, 2=AWAITING_RESULT, 3=CHALLENGE)"
echo ""

if [ "$STATE" != "2" ]; then
  echo "⚠️  DKG is not in AWAITING_RESULT state (stage 2)"
  echo "   Current state: $STATE"
  exit 0
fi

# Get current block
CURRENT_BLOCK=$(cast block-number --rpc-url $RPC_URL | cast --to-dec)
echo "Current block: $CURRENT_BLOCK"
echo ""

# Get DKG parameters
echo "DKG Parameters:"
PARAMS=$(cast call $WR "dkgParameters()" --rpc-url $RPC_URL 2>/dev/null || echo "")
if [ -z "$PARAMS" ] || [ "$PARAMS" = "0x" ]; then
  echo "  ⚠️  Error: Could not fetch DKG parameters"
  echo "     WalletRegistry address: $WR"
  echo "     Check if contract exists and RPC is accessible"
  exit 1
fi

# Parse resultSubmissionTimeout (4th parameter in the tuple)
# Tuple format: (seedTimeout, resultChallengePeriodLength, resultChallengeExtraGas, resultSubmissionTimeout, submitterPrecedencePeriodLength)
# Each value is 32 bytes (64 hex chars)
RESULT_TIMEOUT=$(echo "$PARAMS" | sed 's/0x//' | fold -w 64 | sed -n '4p')
if [ -z "$RESULT_TIMEOUT" ]; then
  echo "  ⚠️  Error: Could not parse resultSubmissionTimeout from parameters"
  echo "     Raw output: $PARAMS"
  exit 1
fi
RESULT_TIMEOUT="0x$RESULT_TIMEOUT"
RESULT_TIMEOUT_DEC=$(cast --to-dec "$RESULT_TIMEOUT" 2>/dev/null || echo "0")
echo "  Result Submission Timeout: $RESULT_TIMEOUT_DEC blocks"
echo ""

# Check if DKG has timed out
HAS_TIMED_OUT=$(cast call $WR "hasDkgTimedOut()" --rpc-url $RPC_URL)
if [ "$HAS_TIMED_OUT" = "0x0000000000000000000000000000000000000000000000000000000000000001" ]; then
  echo "⚠️  DKG has already timed out!"
  echo ""
  echo "   You can reset DKG by calling:"
  echo "   ./scripts/reset-dkg-if-timed-out.sh"
  exit 0
fi

# Try to get DKG start block from events
# Search from a reasonable range (last 10000 blocks or from block 0)
FROM_BLOCK=$((CURRENT_BLOCK - 10000))
if [ "$FROM_BLOCK" -lt 0 ]; then
  FROM_BLOCK=0
fi

DKG_STARTED=$(cast logs --from-block $FROM_BLOCK --to-block latest \
  --address $WR \
  "DkgStarted(uint256,bytes32)" \
  --rpc-url $RPC_URL 2>/dev/null | jq -r 'if type == "array" and length > 0 then .[-1] else empty end' 2>/dev/null || echo "")

if [ -n "$DKG_STARTED" ] && [ "$DKG_STARTED" != "null" ] && [ "$DKG_STARTED" != "" ] && [ "$DKG_STARTED" != "[]" ]; then
  START_BLOCK=$(echo "$DKG_STARTED" | jq -r '.blockNumber' 2>/dev/null)
  if [ -n "$START_BLOCK" ] && [ "$START_BLOCK" != "null" ]; then
    START_BLOCK_DEC=$(cast --to-dec "$START_BLOCK" 2>/dev/null || echo "$START_BLOCK")
    echo "DKG Start Block: $START_BLOCK_DEC"
    echo ""
  
  # Calculate timeout block
  # Timeout = startBlock + resultSubmissionStartBlockOffset + resultSubmissionTimeout
  # For simplicity, we'll use startBlock + resultSubmissionTimeout
  # (resultSubmissionStartBlockOffset is typically 0 unless there was a challenge)
  TIMEOUT_BLOCK=$((START_BLOCK + RESULT_TIMEOUT_DEC))
  BLOCKS_REMAINING=$((TIMEOUT_BLOCK - CURRENT_BLOCK))
  
  echo "Timeout Block: $TIMEOUT_BLOCK"
  echo "Blocks Remaining: $BLOCKS_REMAINING"
  echo ""
  
  # Calculate time
  BLOCK_TIME=15  # seconds per block (typical for development)
  SECONDS_REMAINING=$((BLOCKS_REMAINING * BLOCK_TIME))
  MINUTES_REMAINING=$((SECONDS_REMAINING / 60))
  HOURS_REMAINING=$((MINUTES_REMAINING / 60))
  
  if [ "$BLOCKS_REMAINING" -lt 0 ]; then
    echo "⚠️  DKG has already timed out!"
    echo "   Timeout was $((BLOCKS_REMAINING * -1)) blocks ago"
  else
    echo "Time Remaining:"
    if [ "$HOURS_REMAINING" -gt 0 ]; then
      MINUTES_PART=$((MINUTES_REMAINING % 60))
      echo "  ~$HOURS_REMAINING hours $MINUTES_PART minutes"
    else
      echo "  ~$MINUTES_REMAINING minutes"
    fi
    echo "  ($SECONDS_REMAINING seconds)"
    fi
  else
    echo "⚠️  Could not parse start block from DkgStarted event"
  fi
else
  echo "⚠️  Could not find DkgStarted event"
  echo "   Showing estimated timeout duration:"
  echo ""
  BLOCK_TIME=15  # seconds per block (typical for development)
  SECONDS_TOTAL=$((RESULT_TIMEOUT_DEC * BLOCK_TIME))
  MINUTES_TOTAL=$((SECONDS_TOTAL / 60))
  HOURS_TOTAL=$((MINUTES_TOTAL / 60))
  
  if [ "$HOURS_TOTAL" -gt 0 ]; then
    MINUTES_PART=$((MINUTES_TOTAL % 60))
    echo "  Estimated duration: ~$HOURS_TOTAL hours $MINUTES_PART minutes"
  else
    echo "  Estimated duration: ~$MINUTES_TOTAL minutes"
  fi
  echo "  ($SECONDS_TOTAL seconds)"
fi

echo ""
echo "=========================================="
echo ""
echo "Summary:"
echo "  Stage 2 (AWAITING_RESULT) timeout: $RESULT_TIMEOUT_DEC blocks"
echo "  At 15 seconds per block: ~$((RESULT_TIMEOUT_DEC * 15 / 60)) minutes"
echo ""
echo "The timeout includes:"
echo "  - 20 blocks to confirm DkgStarted event off-chain"
echo "  - 216 blocks for off-chain DKG protocol execution"
echo "  - 300 blocks for result submission (3 blocks × 100 members)"
echo "  Total: 536 blocks"
