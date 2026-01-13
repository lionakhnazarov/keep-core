#!/bin/bash
# Monitor deposit events in real-time

BRIDGE="0xc7BC782Da1AAb7ee5985aC94C575f374FA4C75e5"
RPC_URL="http://localhost:8545"
DEPOSIT_REVEALED_SIG="0xa7382159a693ed317a024daf0fd1ba30805cdf9928ee09550af517c516e2ef05"

echo "=========================================="
echo "Monitoring Deposit Events (Real-time)"
echo "=========================================="
echo "Bridge: $BRIDGE"
echo "Press Ctrl+C to stop"
echo ""

CURRENT_BLOCK=$(cast block-number --rpc-url $RPC_URL 2>/dev/null | cast --to-dec 2>/dev/null || echo "0")
LAST_BLOCK=$((CURRENT_BLOCK - 10))

while true; do
  CURRENT_BLOCK=$(cast block-number --rpc-url $RPC_URL 2>/dev/null | cast --to-dec 2>/dev/null || echo "$LAST_BLOCK")
  
  if [ "$CURRENT_BLOCK" -gt "$LAST_BLOCK" ]; then
    EVENTS=$(cast logs --from-block $((LAST_BLOCK + 1)) --to-block $CURRENT_BLOCK \
      --address $BRIDGE --rpc-url $RPC_URL --json 2>/dev/null || echo "[]")
    
    REVEALED=$(echo "$EVENTS" | jq -r "[.[] | select(.topics[0] == \"$DEPOSIT_REVEALED_SIG\")]")
    COUNT=$(echo "$REVEALED" | jq -r 'length' 2>/dev/null || echo "0")
    
    if [ "$COUNT" != "0" ] && [ "$COUNT" != "null" ]; then
      echo "$REVEALED" | jq -r '.[] | 
        "🔔 [Block \(.blockNumber)] Deposit Revealed!
  TX: \(.transactionHash)
  Depositor: \(.topics[1] | sub("0x000000000000000000000000"; "0x"))
  Wallet PKH: \(.topics[2] | sub("0x000000000000000000000000"; "0x") | sub("000000000000000000000000$"; ""))
  ---"'
    fi
    
    LAST_BLOCK=$CURRENT_BLOCK
  fi
  
  sleep 3
done
