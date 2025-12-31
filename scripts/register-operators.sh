#!/bin/bash
# Script to register operators in WalletRegistry
# Operators must be registered before they can join the sortition pool

set -e

cd "$(dirname "$0")/.."

WR="0x64F6B5b4AeF3F69952d3B8313F33E99AaAb69241"
RPC_URL="http://localhost:8545"

echo "=========================================="
echo "Register Operators in WalletRegistry"
echo "=========================================="
echo ""

# Collect operator addresses from running nodes
declare -a OPERATORS
declare -a NODE_INDICES

for i in {1..5}; do
  PORT=$((9600 + i))
  if curl -s http://localhost:$PORT/diagnostics > /dev/null 2>&1; then
    OPERATOR=$(curl -s http://localhost:$PORT/diagnostics 2>/dev/null | jq -r '.client_info.chain_address' 2>/dev/null || echo "")
    if [ -n "$OPERATOR" ] && [ "$OPERATOR" != "null" ] && [ "$OPERATOR" != "" ]; then
      OPERATORS+=("$OPERATOR")
      NODE_INDICES+=("$i")
      echo "Node $i: $OPERATOR"
    fi
  fi
done

if [ ${#OPERATORS[@]} -eq 0 ]; then
  echo "⚠️  No running nodes found"
  exit 1
fi

echo ""
echo "Checking registration status..."
echo ""

# Check which operators need registration
NEED_REGISTRATION=()
for i in "${!OPERATORS[@]}"; do
  OPERATOR="${OPERATORS[$i]}"
  NODE_IDX="${NODE_INDICES[$i]}"
  
  STAKING_PROVIDER=$(cast call $WR "operatorToStakingProvider(address)" $OPERATOR --rpc-url $RPC_URL 2>/dev/null || echo "0x0000000000000000000000000000000000000000000000000000000000000000")
  
  # Check if staking provider is zero address (not registered)
  # Result is 32 bytes, zero address is 0x0000000000000000000000000000000000000000000000000000000000000000
  if [ "$STAKING_PROVIDER" = "0x0000000000000000000000000000000000000000000000000000000000000000" ]; then
    echo "✗ Node $NODE_IDX ($OPERATOR): NOT REGISTERED"
    NEED_REGISTRATION+=("$OPERATOR:$NODE_IDX")
  else
    # Extract the actual address (last 40 hex chars = 20 bytes)
    ACTUAL_ADDR="0x$(echo "$STAKING_PROVIDER" | sed 's/0x//' | tail -c 41)"
    echo "✓ Node $NODE_IDX ($OPERATOR): Registered (StakingProvider: $ACTUAL_ADDR)"
  fi
done

if [ ${#NEED_REGISTRATION[@]} -eq 0 ]; then
  echo ""
  echo "✅ All operators are already registered!"
  exit 0
fi

echo ""
echo "=========================================="
echo "Registering Operators"
echo "=========================================="
echo ""
echo "⚠️  Note: registerOperator() must be called by the STAKING PROVIDER"
echo "   For self-staking setups, the operator and staking provider are the same"
echo ""

# For each operator that needs registration, we need to:
# 1. Get the staking provider (usually same as operator for self-staking)
# 2. Call registerOperator from the staking provider account

for REG_INFO in "${NEED_REGISTRATION[@]}"; do
  OPERATOR=$(echo "$REG_INFO" | cut -d':' -f1)
  NODE_IDX=$(echo "$REG_INFO" | cut -d':' -f2)
  
  echo "Registering Node $NODE_IDX ($OPERATOR)..."
  
  # For self-staking, staking provider = operator
  # We need to call registerOperator from the staking provider account
  # Since we don't have direct access to the staking provider keyfile here,
  # we'll use the keep-client CLI which handles this properly
  
  CONFIG_FILE="configs/node${NODE_IDX}.toml"
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "  ⚠️  Config file not found: $CONFIG_FILE"
    echo "     Skipping registration for this operator"
    continue
  fi
  
  echo "  Using config: $CONFIG_FILE"
  
  # Use keep-client to register operator
  # This will use the staking provider keyfile from the config
  if KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry register-operator \
    "$OPERATOR" \
    --submit \
    --config "$CONFIG_FILE" \
    --developer 2>&1 | grep -v "You are using a version" | grep -v "Please, make sure" | grep -v "To learn more" | grep -v "Error encountered" | grep -v "No need to generate" | grep -E "(Transaction|hash|SUCCESS|Error|registered)" | head -5; then
    echo "  ✓ Registration submitted"
  else
    echo "  ⚠️  Registration may have failed (check output above)"
  fi
  
  sleep 2
  echo ""
done

echo "=========================================="
echo "Verification"
echo "=========================================="
echo ""

# Verify registration
ALL_REGISTERED=true
for i in "${!OPERATORS[@]}"; do
  OPERATOR="${OPERATORS[$i]}"
  NODE_IDX="${NODE_INDICES[$i]}"
  
  STAKING_PROVIDER=$(cast call $WR "operatorToStakingProvider(address)" $OPERATOR --rpc-url $RPC_URL 2>/dev/null || echo "0x0000000000000000000000000000000000000000000000000000000000000000")
  
  # Check if staking provider is zero address (not registered)
  # Result is 32 bytes, zero address is 0x0000000000000000000000000000000000000000000000000000000000000000
  if [ "$STAKING_PROVIDER" = "0x0000000000000000000000000000000000000000000000000000000000000000" ]; then
    echo "✗ Node $NODE_IDX: Still not registered"
    ALL_REGISTERED=false
  else
    echo "✓ Node $NODE_IDX: Registered"
  fi
done

echo ""
if [ "$ALL_REGISTERED" = true ]; then
  echo "✅ All operators registered successfully!"
  echo ""
  echo "Next step: Join sortition pool"
  echo "  ./scripts/fix-operators-not-in-pool.sh"
else
  echo "⚠️  Some operators failed to register"
  echo ""
  echo "Troubleshooting:"
  echo "  1. Ensure staking provider has stake"
  echo "  2. Ensure staking provider has authorization for WalletRegistry"
  echo "  3. Check that WalletRegistry application is approved in TokenStaking"
  echo "  4. Try manual registration:"
  echo "     KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry register-operator <OPERATOR> --submit --config configs/node<N>.toml --developer"
fi

echo ""
echo "=========================================="
