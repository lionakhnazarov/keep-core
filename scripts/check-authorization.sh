#!/bin/bash
# Script to check operator authorization status

set -e

cd "$(dirname "$0")/.."

WR="0x64F6B5b4AeF3F69952d3B8313F33E99AaAb69241"
RPC_URL="http://localhost:8545"

echo "=========================================="
echo "Check Operator Authorization"
echo "=========================================="
echo ""

# Get minimum authorization
MIN_AUTH=$(cast call $WR "minimumAuthorization()" --rpc-url $RPC_URL | cast --to-dec)
MIN_AUTH_T=$(echo "scale=0; $MIN_AUTH / 1000000000000000000" | bc)
echo "Minimum Authorization: $MIN_AUTH_T T ($MIN_AUTH wei)"
echo ""

# Collect operator addresses
declare -a OPERATORS
declare -a NODE_INDICES

for i in {1..5}; do
  PORT=$((9600 + i))
  if curl -s http://localhost:$PORT/diagnostics > /dev/null 2>&1; then
    OPERATOR=$(curl -s http://localhost:$PORT/diagnostics 2>/dev/null | jq -r '.client_info.chain_address' 2>/dev/null || echo "")
    if [ -n "$OPERATOR" ] && [ "$OPERATOR" != "null" ] && [ "$OPERATOR" != "" ]; then
      OPERATORS+=("$OPERATOR")
      NODE_INDICES+=("$i")
    fi
  fi
done

if [ ${#OPERATORS[@]} -eq 0 ]; then
  echo "⚠️  No running nodes found"
  exit 1
fi

echo "Checking authorization for ${#OPERATORS[@]} operators..."
echo ""

ALL_AUTHORIZED=true

for i in "${!OPERATORS[@]}"; do
  OPERATOR="${OPERATORS[$i]}"
  NODE_IDX="${NODE_INDICES[$i]}"
  
  echo "Node $NODE_IDX: $OPERATOR"
  
  # Get staking provider
  STAKING_PROVIDER=$(cast call $WR "operatorToStakingProvider(address)" $OPERATOR --rpc-url $RPC_URL 2>/dev/null | tail -c 41 | sed 's/^/0x/')
  
  if [ "$STAKING_PROVIDER" = "0x0000000000000000000000000000000000000000" ]; then
    echo "  ✗ NOT REGISTERED"
    ALL_AUTHORIZED=false
  else
    echo "  StakingProvider: $STAKING_PROVIDER"
    
    # Get eligible stake (authorization)
    ELIGIBLE_STAKE=$(cast call $WR "eligibleStake(address)" $STAKING_PROVIDER --rpc-url $RPC_URL 2>/dev/null | cast --to-dec || echo "0")
    ELIGIBLE_STAKE_T=$(echo "scale=2; $ELIGIBLE_STAKE / 1000000000000000000" | bc)
    
    echo "  Eligible Stake: $ELIGIBLE_STAKE_T T ($ELIGIBLE_STAKE wei)"
    
    # Use bc for large integer comparison
    COMPARE=$(echo "$ELIGIBLE_STAKE < $MIN_AUTH" | bc)
    if [ "$COMPARE" -eq 1 ]; then
      echo "  ✗ Authorization BELOW minimum ($MIN_AUTH_T T required)"
      ALL_AUTHORIZED=false
    else
      echo "  ✓ Authorization OK"
    fi
  fi
  
  echo ""
done

echo "=========================================="
if [ "$ALL_AUTHORIZED" = true ]; then
  echo "✅ All operators have sufficient authorization!"
else
  echo "⚠️  Some operators need authorization"
  echo ""
  echo "To authorize operators, use:"
  echo "  ./scripts/initialize.sh"
  echo ""
  echo "Or manually authorize each operator:"
  echo "  STAKING=\"<TokenStaking address>\""
  echo "  STAKING_PROVIDER=\"<staking provider address>\""
  echo "  WR=\"$WR\""
  echo "  AMOUNT=\"$MIN_AUTH\""
  echo "  cast send \$STAKING \"increaseAuthorization(address,address,uint96)\" \\"
  echo "    \$STAKING_PROVIDER \$WR \$AMOUNT \\"
  echo "    --rpc-url $RPC_URL --unlocked --from <authorizer>"
fi
echo "=========================================="
