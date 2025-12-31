#!/bin/bash
# Debug why DKG result is not being submitted

set -eou pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

CONFIG_FILE="${1:-configs/config.toml}"

echo "=========================================="
echo "Debug DKG Result Submission"
echo "=========================================="
echo ""

# Check current state
echo "1. Checking DKG state..."
STATE=$(KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry get-wallet-creation-state \
  --config "$CONFIG_FILE" --developer 2>&1 | grep -E "^[0-9]+$" | head -1 || echo "")
echo "   State: $STATE (2=AWAITING_RESULT, 3=CHALLENGE, 0=IDLE)"
echo ""

# Check timeout
echo "2. Checking timeout status..."
TIMED_OUT=$(KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry has-dkg-timed-out \
  --config "$CONFIG_FILE" --developer 2>&1 | grep -iE "true|false" | head -1 || echo "false")
echo "   Timed Out: $TIMED_OUT"
echo ""

# Check DKG parameters
echo "3. Checking DKG parameters..."
DKG_PARAMS=$(KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry dkg-parameters \
  --config "$CONFIG_FILE" --developer 2>&1 || echo "")
SUBMISSION_TIMEOUT=$(echo "$DKG_PARAMS" | grep -iE "submission.*timeout|resultSubmissionTimeout" | grep -oE "[0-9]+" | head -1 || echo "30")
echo "   Result Submission Timeout: $SUBMISSION_TIMEOUT blocks"
echo ""

# Check recent DKG events
echo "4. Checking recent DKG events..."
WR=$(jq -r '.address' solidity/ecdsa/deployments/development/WalletRegistry.json 2>/dev/null || echo "")
if [ -n "$WR" ]; then
    CURRENT_BLOCK=$(cast block-number --rpc-url http://localhost:8545 2>/dev/null || echo "0")
    echo "   Current Block: $CURRENT_BLOCK"
    
    # Get latest DkgStarted event
    START_BLOCK=$(cast logs --from-block latest-200 --to-block latest \
      --address "$WR" \
      --topic "0x$(cast keccak 'DkgStarted(uint256)' | cut -c1-66)" \
      --rpc-url http://localhost:8545 2>/dev/null | tail -1 | grep -oE "blockNumber.*[0-9]+" | grep -oE "[0-9]+" || echo "")
    
    if [ -n "$START_BLOCK" ]; then
        BLOCKS_ELAPSED=$((CURRENT_BLOCK - START_BLOCK))
        echo "   DKG Start Block: $START_BLOCK"
        echo "   Blocks Elapsed: $BLOCKS_ELAPSED"
        echo "   Timeout Blocks: $SUBMISSION_TIMEOUT"
        
        if [ "$BLOCKS_ELAPSED" -gt "$SUBMISSION_TIMEOUT" ]; then
            echo "   ⚠ TIMEOUT EXCEEDED - This is why submission isn't happening!"
        fi
    fi
fi
echo ""

# Check logs for protocol progress
echo "5. Checking protocol progress in logs..."
echo "   Looking for protocol phases..."

PROTOCOL_STARTED=false
PROTOCOL_COMPLETED=false
RESULT_READY=false
SIGNATURES_COLLECTED=false
ABORTED=false

for i in {1..10}; do
    LOG_FILE="logs/node${i}.log"
    if [ ! -f "$LOG_FILE" ]; then
        continue
    fi
    
    if grep -q "starting announcement phase\|starting.*phase" "$LOG_FILE" 2>/dev/null; then
        PROTOCOL_STARTED=true
    fi
    
    if grep -q "protocol.*complete\|DKG.*complete" "$LOG_FILE" 2>/dev/null; then
        PROTOCOL_COMPLETED=true
    fi
    
    if grep -q "submitting DKG result\|waiting.*block.*submit" "$LOG_FILE" 2>/dev/null; then
        RESULT_READY=true
    fi
    
    if grep -q "signature.*collected\|member.*sign" "$LOG_FILE" 2>/dev/null; then
        SIGNATURES_COLLECTED=true
    fi
    
    if grep -q "aborting DKG protocol execution\|no longer awaiting" "$LOG_FILE" 2>/dev/null; then
        ABORTED=true
    fi
done

if [ "$PROTOCOL_STARTED" = "true" ]; then
    echo "   ✓ Protocol started"
else
    echo "   ✗ Protocol did NOT start"
fi

if [ "$PROTOCOL_COMPLETED" = "true" ]; then
    echo "   ✓ Protocol completed"
else
    echo "   ✗ Protocol did NOT complete"
fi

if [ "$RESULT_READY" = "true" ]; then
    echo "   ✓ Result ready for submission"
else
    echo "   ✗ Result NOT ready"
fi

if [ "$SIGNATURES_COLLECTED" = "true" ]; then
    echo "   ✓ Signatures collected"
else
    echo "   ✗ Signatures NOT collected"
fi

if [ "$ABORTED" = "true" ]; then
    echo "   ⚠ Protocol ABORTED (likely due to timeout)"
fi
echo ""

# Check for specific error messages
echo "6. Checking for specific errors..."
RECENT_ERRORS=$(tail -500 logs/node*.log 2>/dev/null | grep -iE "could not submit|insufficient.*signature|quorum|timeout.*abort" | tail -10 || echo "")
if [ -n "$RECENT_ERRORS" ]; then
    echo "   Recent errors found:"
    echo "$RECENT_ERRORS" | sed 's/^/   /'
else
    echo "   No specific submission errors found"
fi
echo ""

# Summary and recommendations
echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""

if [ "$TIMED_OUT" = "true" ] || [ "$ABORTED" = "true" ]; then
    echo "❌ ROOT CAUSE: DKG is timing out before protocol can complete"
    echo ""
    echo "The protocol needs more time than the timeout allows."
    echo ""
    echo "Solutions:"
    echo ""
    echo "1. Speed up block mining during DKG:"
    echo "   ./scripts/mine-blocks-fast.sh 30 0.1"
    echo ""
    echo "2. Use auto-reset monitor:"
    echo "   ./scripts/auto-reset-dkg.sh configs/config.toml &"
    echo ""
    echo "3. Increase timeout (if possible):"
    echo "   # Update resultSubmissionTimeout via governance"
    echo ""
    echo "4. Check if protocol is actually completing:"
    echo "   tail -f logs/node*.log | grep -E 'protocol.*complete|phase.*complete'"
    echo ""
elif [ "$PROTOCOL_COMPLETED" = "true" ] && [ "$RESULT_READY" = "false" ]; then
    echo "⚠ Protocol completed but result not ready for submission"
    echo ""
    echo "Possible causes:"
    echo "- Not enough signatures collected (need GroupQuorum)"
    echo "- Result validation failed"
    echo "- Submission delay blocks not reached"
    echo ""
    echo "Check logs for:"
    echo "  - Signature collection messages"
    echo "  - Result validation errors"
    echo "  - 'waiting for block X to submit' messages"
    echo ""
else
    echo "Protocol may still be running..."
    echo "Monitor with: tail -f logs/node*.log | grep -i dkg"
fi
echo ""
