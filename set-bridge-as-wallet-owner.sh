#!/bin/bash
# Set Bridge as walletOwner in WalletRegistry

BRIDGE="0xc7BC782Da1AAb7ee5985aC94C575f374FA4C75e5"
WR="0xd49141e044801DEE237993deDf9684D59fafE2e6"
WR_GOV="0x1bef6019c28a61130c5c04f6b906a16c85397cea"
RPC_URL="http://localhost:8545"

# Get governance owner
OWNER=$(cast call $WR_GOV "owner()" --rpc-url $RPC_URL 2>/dev/null | sed 's/0x000000000000000000000000/0x/')
echo "Governance Owner: $OWNER"

# Get an account with funds
ACCOUNT=$(cast rpc eth_accounts --rpc-url $RPC_URL 2>/dev/null | jq -r '.[0]')
echo "Funding Account: $ACCOUNT"
echo ""

# Check owner balance
OWNER_BALANCE=$(cast balance $OWNER --rpc-url $RPC_URL 2>/dev/null)
OWNER_BALANCE_ETH=$(echo "scale=4; $OWNER_BALANCE / 1000000000000000000" | bc)
echo "Owner balance: $OWNER_BALANCE_ETH ETH"

if (( $(echo "$OWNER_BALANCE_ETH < 0.01" | bc -l) )); then
  echo ""
  echo "Funding owner account..."
  cast send $OWNER --value $(cast --to-wei 1 ether) --rpc-url $RPC_URL --unlocked --from $ACCOUNT 2>&1 | grep -E "transactionHash|blockHash|Error" | head -3
  sleep 2
fi

echo ""
echo "Step 1: Begin walletOwner update..."
cast send $WR_GOV "beginWalletOwnerUpdate(address)" $BRIDGE \
  --rpc-url $RPC_URL --unlocked --from $OWNER 2>&1 | grep -E "transactionHash|blockHash|Error" | head -3

sleep 2

echo ""
echo "Step 2: Checking delay..."
DELAY=$(cast call $WR_GOV "governanceDelay()" --rpc-url $RPC_URL 2>/dev/null | cast --to-dec 2>/dev/null)
echo "Governance delay: $DELAY seconds"

PENDING_UPDATE=$(cast call $WR_GOV "walletOwnerChangeInitiated()" --rpc-url $RPC_URL 2>/dev/null | cast --to-dec 2>/dev/null)
if [ "$PENDING_UPDATE" != "0" ]; then
  echo ""
  echo "Waiting $DELAY seconds for governance delay..."
  sleep $DELAY
  
  echo ""
  echo "Step 3: Finalizing walletOwner update..."
  cast send $WR_GOV "finalizeWalletOwnerUpdate()" \
    --rpc-url $RPC_URL --unlocked --from $OWNER 2>&1 | grep -E "transactionHash|blockHash|Error" | head -3
  
  sleep 2
  
  echo ""
  echo "Verifying..."
  NEW_OWNER=$(cast call $WR "walletOwner()" --rpc-url $RPC_URL 2>/dev/null | sed 's/0x000000000000000000000000/0x/')
  # Compare addresses case-insensitively (Ethereum addresses are case-insensitive)
  if [ "$(echo $NEW_OWNER | tr '[:upper:]' '[:lower:]')" = "$(echo $BRIDGE | tr '[:upper:]' '[:lower:]')" ]; then
    echo "✅ Bridge is now walletOwner!"
    echo ""
    echo "Next steps:"
    echo "1. Request a new wallet: ./scripts/request-new-wallet.sh"
    echo "2. Wait for DKG to complete"
    echo "3. Check status: ./check-all-wallets-bridge.sh"
  else
    echo "❌ Update failed. Current owner: $NEW_OWNER"
    echo "   Expected Bridge: $BRIDGE"
  fi
else
  echo "❌ Failed to begin update"
fi
