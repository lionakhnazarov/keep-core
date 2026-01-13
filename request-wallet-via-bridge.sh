#!/bin/bash
# Request new wallet via Bridge contract (which forwards to WalletRegistry)

BRIDGE="0xc7BC782Da1AAb7ee5985aC94C575f374FA4C75e5"
RPC_URL="http://localhost:8545"
ACCOUNT=$(cast rpc eth_accounts --rpc-url $RPC_URL 2>/dev/null | jq -r '.[0]')

echo "=========================================="
echo "Requesting New Wallet via Bridge"
echo "=========================================="
echo ""
echo "Bridge: $BRIDGE"
echo "Account: $ACCOUNT"
echo ""

# BitcoinTx.UTXO is a struct: (bytes32 txHash, uint32 outputIndex, uint64 amount)
# For NO_MAIN_UTXO (no active wallet), we pass zeros:
# txHash = 0x0000...0000 (32 bytes)
# outputIndex = 0
# amount = 0

NO_MAIN_UTXO="(0x0000000000000000000000000000000000000000000000000000000000000000,0,0)"

echo "Calling Bridge.requestNewWallet($NO_MAIN_UTXO)..."
cast send $BRIDGE \
  "requestNewWallet((bytes32,uint32,uint64))" \
  "$NO_MAIN_UTXO" \
  --rpc-url $RPC_URL \
  --unlocked \
  --from $ACCOUNT \
  --gas-limit 500000 \
  2>&1 | grep -E "transactionHash|blockHash|status|Error" | head -10

echo ""
echo "If successful, DKG will start. Monitor progress with:"
echo "  ./scripts/wait-for-dkg-completion.sh"
echo "  tail -f logs/node1.log | grep -i dkg"
