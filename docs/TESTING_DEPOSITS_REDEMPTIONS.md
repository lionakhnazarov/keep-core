# Testing Deposits and Redemptions

This guide explains how to test the deposit (mint tBTC) and redemption (burn tBTC) processes in a local development environment.

## Overview

The tBTC system allows users to:
1. **Deposit**: Send Bitcoin to a deposit address → Receive tBTC tokens on Ethereum
2. **Redemption**: Burn tBTC tokens → Receive Bitcoin back

## Prerequisites

1. **DKG completed**: A wallet must be created via DKG before deposits/redemptions can be processed
2. **Bridge contract deployed**: The Bridge contract must be deployed and configured
3. **WalletRegistry configured**: WalletRegistry must have a walletOwner set (typically Bridge)

## Testing Deposits (Minting tBTC)

### Step 1: Ensure Wallet Exists

First, verify that a wallet has been created:

```bash
# Use the check-wallet-status script (recommended)
./scripts/check-wallet-status.sh

# Or manually check for WalletCreated events
WR="0x64F6B5b4AeF3F69952d3B8313F33E99AaAb69241"
FROM_BLOCK=$(cast block-number --rpc-url http://localhost:8545 | cast --to-dec)
FROM_BLOCK=$((FROM_BLOCK - 1000))

cast logs --from-block $FROM_BLOCK --to-block latest \
  --address $WR \
  "WalletCreated(bytes32,bytes32,bytes32)" \
  --rpc-url http://localhost:8545
```

**Note**: `WalletRegistry` doesn't have `getWallets()` or `getWalletCount()` functions. Wallets are stored in a mapping and accessed by wallet ID. Use events to find created wallets.

If no wallets exist, trigger DKG first:
```bash
./scripts/request-new-wallet.sh
```

### Step 2: Get Wallet Public Key

Once a wallet is created, you need its public key to generate a deposit address:

```bash
# Get wallet ID from WalletCreated event
WR="0x64F6B5b4AeF3F69952d3B8313F33E99AaAb69241"
FROM_BLOCK=$(cast block-number --rpc-url http://localhost:8545 | cast --to-dec)
FROM_BLOCK=$((FROM_BLOCK - 1000))

# Get the latest wallet ID from events
WALLET_ID=$(cast logs --from-block $FROM_BLOCK --to-block latest \
  --address $WR \
  "WalletCreated(bytes32,bytes32,bytes32)" \
  --rpc-url http://localhost:8545 | jq -r '.[-1].topics[1]')

# Get wallet public key (returns bytes - uncompressed public key)
cast call $WR "getWalletPublicKey(bytes32)" $WALLET_ID --rpc-url http://localhost:8545

# Or use the check-wallet-status script which shows all wallets
./scripts/check-wallet-status.sh
```

### Step 3: Generate Deposit Script

The deposit script is a Bitcoin script that encodes:
- Depositor address (Ethereum address)
- Blinding factor (8 bytes)
- Wallet public key hash (20 bytes)
- Refund public key hash (20 bytes)
- Refund locktime (4 bytes)

For development/testing, you can use simplified scripts or mock the Bitcoin deposit.

### Step 4: Submit Deposit Reveal

In a real system, deposits are revealed on-chain after Bitcoin transactions are confirmed. For testing:

```bash
# Note: This requires the actual Bridge contract (not BridgeStub)
# BridgeStub is minimal and doesn't implement deposit/redemption logic

BRIDGE="0x8aca8D4Ad7b4f2768d1c13018712Da6E3887a79f"

# Check Bridge contract methods
cast abi $BRIDGE --rpc-url http://localhost:8545 | grep -i deposit
```

## Testing Redemptions (Burning tBTC)

### Step 1: Check tBTC Balance

First, verify you have tBTC tokens to redeem:

```bash
# Get tBTC token address (if deployed)
# In development, tBTC might be a stub or ERC20 token

# Check balance
TBTC="<tBTC_TOKEN_ADDRESS>"
ACCOUNT="<YOUR_ACCOUNT>"
cast call $TBTC "balanceOf(address)" $ACCOUNT --rpc-url http://localhost:8545 | cast --to-dec
```

### Step 2: Request Redemption

Request a redemption through the Bridge contract:

```bash
BRIDGE="0x8aca8D4Ad7b4f2768d1c13018712Da6E3887a79f"
WALLET_PUBKEY_HASH="<20-byte wallet public key hash>"
MAIN_UTXO='{"txHash":"0x...","txOutputIndex":0,"txOutputValue":100000000}'
REDEEMER_OUTPUT_SCRIPT="<Bitcoin output script>"
AMOUNT="100000000"  # Amount in satoshis

cast send $BRIDGE "requestRedemption(bytes20,tuple,bytes,uint64)" \
  $WALLET_PUBKEY_HASH \
  "$MAIN_UTXO" \
  $REDEEMER_OUTPUT_SCRIPT \
  $AMOUNT \
  --rpc-url http://localhost:8545 \
  --unlocked \
  --from $(cast rpc eth_accounts --rpc-url http://localhost:8545 | jq -r '.[0]')
```

### Step 3: Monitor Redemption Status

Check the status of your redemption request:

```bash
# Get pending redemptions for a wallet
cast call $BRIDGE "getPendingRedemptions(bytes20)" $WALLET_PUBKEY_HASH --rpc-url http://localhost:8545
```

## Using Keep Core Client for Testing

The Keep Core client handles deposits and redemptions automatically. To test with the client:

### 1. Start Keep Core Client

```bash
# Start client with tBTC application enabled
./keep-client start \
  --config config.toml \
  --ethereum.url http://localhost:8545
```

### 2. Monitor Logs

Watch for deposit and redemption events:

```bash
# Monitor logs for deposit sweep events
tail -f logs/node1.log | grep -i deposit

# Monitor logs for redemption events
tail -f logs/node1.log | grep -i redemption
```

### 3. Check Client Status

```bash
# Check if client is processing deposits/redemptions
curl http://localhost:9601/metrics | grep -i tbtc
```

## Development Environment Limitations

**Important**: The `BridgeStub` contract is a minimal stub for development and **does not implement**:
- Deposit reveal logic
- Redemption request processing
- Bitcoin transaction verification
- tBTC token minting/burning

For full deposit/redemption testing, you need:
1. **Full Bridge contract** (not BridgeStub)
2. **Bitcoin testnet connection** (or local Bitcoin node)
3. **SPV proof verification** (for Bitcoin transaction proofs)
4. **tBTC token contract** (ERC20 token)

## Testing with Integration Tests

The codebase includes integration tests for deposits and redemptions:

```bash
# Run deposit sweep tests
cd pkg/tbtc
go test -v -run TestDepositSweepAction_Execute

# Run redemption tests
go test -v -run TestRedemptionAction_Execute
```

## Manual Testing Scripts

### Check Wallet Status

```bash
#!/bin/bash
# scripts/check-wallet-status.sh

WR="0x64F6B5b4AeF3F69952d3B8313F33E99AaAb69241"

echo "=== Wallet Status ==="
WALLET_COUNT=$(cast call $WR "getWalletCount()" --rpc-url http://localhost:8545 | cast --to-dec)
echo "Total wallets: $WALLET_COUNT"

if [ "$WALLET_COUNT" -gt 0 ]; then
  echo ""
  echo "Wallets:"
  cast call $WR "getWallets()" --rpc-url http://localhost:8545 | jq -r '.[]' | while read wallet_id; do
    echo "  - $wallet_id"
    # Get public key
    PUBKEY=$(cast call $WR "getWalletPublicKey(bytes32)" $wallet_id --rpc-url http://localhost:8545)
    echo "    Public Key: $PUBKEY"
  done
else
  echo "No wallets created yet. Run: ./scripts/request-new-wallet.sh"
fi
```

### Monitor Deposit/Redemption Events

```bash
#!/bin/bash
# scripts/monitor-tbtc-events.sh

BRIDGE="0x8aca8D4Ad7b4f2768d1c13018712Da6E3887a79f"
FROM_BLOCK=$(cast block-number --rpc-url http://localhost:8545 | cast --to-dec)
FROM_BLOCK=$((FROM_BLOCK - 100))

echo "=== Recent tBTC Events ==="
echo "From block: $FROM_BLOCK"
echo ""

# Check for deposit events
echo "Deposit Events:"
cast logs --from-block $FROM_BLOCK --to-block latest \
  --address $BRIDGE \
  "DepositRevealed(bytes32,bytes32,address,uint256,bytes20,bytes20,uint32,bytes32)" \
  --rpc-url http://localhost:8545 2>/dev/null || echo "  None found"

# Check for redemption events
echo ""
echo "Redemption Events:"
cast logs --from-block $FROM_BLOCK --to-block latest \
  --address $BRIDGE \
  "RedemptionRequested(bytes32,bytes20,address,bytes,uint64,uint64,uint64)" \
  --rpc-url http://localhost:8545 2>/dev/null || echo "  None found"
```

## Next Steps

1. **Deploy Full Bridge Contract**: Replace BridgeStub with the full Bridge contract
2. **Set Up Bitcoin Testnet**: Connect to Bitcoin testnet or run a local Bitcoin node
3. **Configure SPV**: Set up Simplified Payment Verification for Bitcoin transactions
4. **Deploy tBTC Token**: Deploy the tBTC ERC20 token contract
5. **Test End-to-End**: Perform full deposit → mint → redemption → burn flow

## References

- [tBTC v2 Documentation](https://docs.threshold.network/)
- [Bridge Contract Interface](./pkg/chain/ethereum/tbtc/gen/contract/Bridge.go)
- [Deposit Test Scenarios](./pkg/tbtc/internal/test/)
- [Redemption Test Scenarios](./pkg/tbtc/internal/test/)
