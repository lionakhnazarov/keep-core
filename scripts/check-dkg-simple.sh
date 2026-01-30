#!/bin/bash
# Simple script to check DKG status using cast commands

WR="0x64F6B5b4AeF3F69952d3B8313F33E99AaAb69241"
RPC="http://localhost:8545"

echo "=========================================="
echo "DKG Status Check (Simple)"
echo "=========================================="
echo "WalletRegistry: $WR"
echo ""

# Method 1: Check wallet creation state (returns 0=IDLE, 1=AWAITING_SEED, 2=AWAITING_RESULT, 3=CHALLENGE)
echo "1. Wallet Creation State:"
STATE=$(cast call $WR "getWalletCreationState()" --rpc-url $RPC 2>/dev/null | cast --to-dec 2>/dev/null || echo "error")
case $STATE in
  0) echo "   IDLE" ;;
  1) echo "   AWAITING_SEED" ;;
  2) echo "   AWAITING_RESULT" ;;
  3) echo "   CHALLENGE" ;;
  *) echo "   Error reading state" ;;
esac

# Method 2: Check if sortition pool is locked
echo ""
echo "2. Sortition Pool Locked:"
SP_RESULT=$(cast call $WR "sortitionPool()" --rpc-url $RPC 2>/dev/null)
SP=$(echo "$SP_RESULT" | sed 's/0x000000000000000000000000//' | sed 's/^/0x/')
if [ -n "$SP" ] && [ "$SP" != "0x0000000000000000000000000000000000000000" ] && [ "$SP" != "0x" ]; then
  IS_LOCKED=$(cast call $SP "isLocked()" --rpc-url $RPC 2>/dev/null | cast --to-bool 2>/dev/null || echo "error")
  if [ "$IS_LOCKED" = "true" ]; then
    echo "   Yes (pool is locked)"
  elif [ "$IS_LOCKED" = "false" ]; then
    echo "   No (pool is unlocked)"
  else
    echo "   Error checking lock status"
  fi
else
  echo "   Error: Could not get sortition pool address"
fi

# Method 3: Check DKG timeout
echo ""
echo "3. DKG Timed Out:"
TIMED_OUT=$(cast call $WR "hasDkgTimedOut()" --rpc-url $RPC 2>/dev/null | cast --to-bool 2>/dev/null || echo "error")
if [ "$TIMED_OUT" = "true" ]; then
  echo "   Yes"
elif [ "$TIMED_OUT" = "false" ]; then
  echo "   No"
else
  echo "   Error checking timeout"
fi

echo ""
echo "=========================================="
echo ""
echo "To check DKG events, use:"
echo "  cast logs --from-block latest-1000 --to-block latest \\"
echo "    --address $WR \\"
echo "    --rpc-url $RPC | grep -E '(DkgStarted|DkgStateLocked|DkgResult)'"
