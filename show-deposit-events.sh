#!/bin/bash
# Show all deposit-related events from Bridge

BRIDGE="0xc7BC782Da1AAb7ee5985aC94C575f374FA4C75e5"
RPC_URL="http://localhost:8545"

echo "=========================================="
echo "Deposit Events Summary"
echo "=========================================="
echo "Bridge: $BRIDGE"
echo ""

# Get current block
CURRENT_BLOCK=$(cast block-number --rpc-url $RPC_URL 2>/dev/null | cast --to-dec 2>/dev/null || echo "0")
FROM_BLOCK=0

echo "Scanning blocks $FROM_BLOCK to $CURRENT_BLOCK (from beginning)"
echo ""

# Get all events from Bridge and filter for DepositRevealed
echo "=== DepositRevealed Events ==="
ALL_EVENTS=$(cast logs --from-block $FROM_BLOCK --to-block latest \
  --address $BRIDGE \
  --rpc-url $RPC_URL \
  --json 2>/dev/null || echo "[]")

# Filter for DepositRevealed event
DEPOSIT_REVEALED_SIG="0xa7382159a693ed317a024daf0fd1ba30805cdf9928ee09550af517c516e2ef05"
REVEALED=$(echo "$ALL_EVENTS" | jq -r "[.[] | select(.topics[0] == \"$DEPOSIT_REVEALED_SIG\")]")

REVEALED_COUNT=$(echo "$REVEALED" | jq -r 'length' 2>/dev/null || echo "0")
echo "Found $REVEALED_COUNT deposit(s) revealed"
echo ""

if [ "$REVEALED_COUNT" != "0" ] && [ "$REVEALED_COUNT" != "null" ]; then
  echo "$REVEALED" | jq -r '.[] | 
    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Block: \(.blockNumber)
Transaction: \(.transactionHash)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Depositor: \(.topics[1] | sub("0x000000000000000000000000"; "0x"))
Wallet PKH: \(.topics[2] | sub("0x000000000000000000000000"; "0x") | sub("000000000000000000000000$"; ""))
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Event Data: \(.data)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"'
fi

echo ""

# Check for DepositSwept events
echo "=== DepositSwept Events ==="
DEPOSIT_SWEPT_SIG=$(cast sig-event "DepositSwept(bytes32,bytes20)" 2>/dev/null || echo "")
if [ -n "$DEPOSIT_SWEPT_SIG" ]; then
  SWEPT=$(echo "$ALL_EVENTS" | jq -r "[.[] | select(.topics[0] == \"$DEPOSIT_SWEPT_SIG\")]")
  SWEPT_COUNT=$(echo "$SWEPT" | jq -r 'length' 2>/dev/null || echo "0")
  echo "Found $SWEPT_COUNT deposit(s) swept"
  
  if [ "$SWEPT_COUNT" != "0" ] && [ "$SWEPT_COUNT" != "null" ]; then
    echo "$SWEPT" | jq -r '.[] | 
      "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Block: \(.blockNumber)
Transaction: \(.transactionHash)
Funding TX Hash: \(.topics[1])
Wallet PKH: \(.topics[2] | sub("0x000000000000000000000000"; "0x"))
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"'
  fi
else
  echo "No DepositSwept events found"
fi

echo ""
echo "=========================================="
echo "To monitor in real-time, run:"
echo "  ./monitor-deposit-events.sh"
echo ""
