#!/bin/bash
# Script to check if operators are in the sortition pool using cast

set -e

cd "$(dirname "$0")/.."

WR="0x64F6B5b4AeF3F69952d3B8313F33E99AaAb69241"
RPC_URL="http://localhost:8545"

echo "=========================================="
echo "Check Operators in Sortition Pool"
echo "=========================================="
echo ""

# Get SortitionPool address
SP=$(cast call $WR "sortitionPool()" --rpc-url $RPC_URL | sed 's/0x000000000000000000000000//' | sed 's/^/0x/')
echo "WalletRegistry: $WR"
echo "SortitionPool: $SP"
echo ""

# Check if nodes are running and get operator addresses
echo "Checking nodes..."
echo ""

OPERATORS=()
NODE_COUNT=0

# Try to get operator addresses from running nodes
for i in {1..5}; do
  PORT=$((9600 + i))
  if curl -s http://localhost:$PORT/diagnostics > /dev/null 2>&1; then
    OPERATOR=$(curl -s http://localhost:$PORT/diagnostics 2>/dev/null | jq -r '.client_info.chain_address' 2>/dev/null || echo "")
    if [ -n "$OPERATOR" ] && [ "$OPERATOR" != "null" ] && [ "$OPERATOR" != "" ]; then
      OPERATORS+=("$OPERATOR")
      NODE_COUNT=$((NODE_COUNT + 1))
      echo "Node $i: $OPERATOR"
    fi
  fi
done

if [ ${#OPERATORS[@]} -eq 0 ]; then
  echo "⚠️  No running nodes found or could not get operator addresses"
  echo ""
  echo "You can also check specific operators manually:"
  echo "  OPERATOR=\"0x...\""
  echo "  cast call $SP \"isOperatorInPool(address)\" \$OPERATOR --rpc-url $RPC_URL"
  exit 0
fi

echo ""
echo "Checking sortition pool status..."
echo ""

ALL_IN_POOL=true
IN_POOL_COUNT=0

for OPERATOR in "${OPERATORS[@]}"; do
  # Check if operator is in pool
  IS_IN_POOL=$(cast call $SP "isOperatorInPool(address)" $OPERATOR --rpc-url $RPC_URL 2>/dev/null || echo "0x0")
  
  if [ "$IS_IN_POOL" = "0x0000000000000000000000000000000000000000000000000000000000000001" ]; then
    echo "✓ $OPERATOR: IN POOL"
    IN_POOL_COUNT=$((IN_POOL_COUNT + 1))
    
    # Get operator ID
    OPERATOR_ID=$(cast call $SP "getOperatorID(address)" $OPERATOR --rpc-url $RPC_URL 2>/dev/null | cast --to-dec || echo "N/A")
    if [ "$OPERATOR_ID" != "N/A" ] && [ "$OPERATOR_ID" != "0" ]; then
      echo "    Operator ID: $OPERATOR_ID"
    fi
    
    # Get operator weight
    WEIGHT=$(cast call $SP "getPoolWeight(address)" $OPERATOR --rpc-url $RPC_URL 2>/dev/null | cast --to-dec || echo "N/A")
    if [ "$WEIGHT" != "N/A" ] && [ "$WEIGHT" != "0" ]; then
      echo "    Weight: $WEIGHT"
    fi
  else
    echo "✗ $OPERATOR: NOT IN POOL"
    ALL_IN_POOL=false
  fi
done

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo "Total nodes checked: ${#OPERATORS[@]}"
echo "Operators in pool: $IN_POOL_COUNT"
echo "Operators not in pool: $((${#OPERATORS[@]} - IN_POOL_COUNT))"
echo ""

# Check pool state
POOL_LOCKED=$(cast call $SP "isLocked()" --rpc-url $RPC_URL 2>/dev/null || echo "0x0")
if [ "$POOL_LOCKED" = "0x0000000000000000000000000000000000000000000000000000000000000001" ]; then
  echo "Pool State: LOCKED (DKG in progress)"
else
  echo "Pool State: UNLOCKED"
fi

echo ""

if [ "$ALL_IN_POOL" = true ]; then
  echo "✅ All operators are in the sortition pool!"
else
  echo "⚠️  Some operators are NOT in the pool"
  echo ""
  echo "To add operators to the pool, run:"
  echo "  ./scripts/fix-operators-not-in-pool.sh"
fi

echo ""
echo "=========================================="
