# Deposit Testing Guide

## Current Status

✅ **Bridge Stub Deployed**: `0xc0a2ee534F004a4ec2EFA541489acBD5ff4bBA99`  
✅ **Wallets Created**: 2 wallets registered in WalletRegistry  
❌ **Bridge State**: Unknown (Bridge stub doesn't track wallets)

## Understanding Bridge Stub vs Full Bridge

The **Bridge stub** (`solidity/tbtc-stub`) is minimal and only implements:
- ✅ `requestNewWallet()` - triggers DKG
- ✅ `__ecdsaWalletCreatedCallback()` - receives wallet creation callbacks
- ❌ **Does NOT implement**: `revealDeposit()`, wallet tracking, deposit events

The **Full Bridge** (`tmp/tbtc-v2/solidity`) implements complete deposit functionality.

## Option 1: Test Deposits with Full Bridge Contract (Recommended)

### Step 1: Deploy Full Bridge Contract

```bash
cd tmp/tbtc-v2/solidity
npx hardhat deploy --network development --tags Bridge --reset
```

This will deploy the full Bridge contract with deposit functionality.

### Step 2: Update WalletOwner to Full Bridge

```bash
cd ../../..
cd solidity/ecdsa
npx hardhat run scripts/init-wallet-owner.ts --network development
```

This will set the full Bridge as walletOwner (it will prefer Bridge stub, so you may need to manually update).

### Step 3: Create New Wallet (if needed)

Since wallets were created with Bridge stub, create a new wallet so the full Bridge receives the callback:

```bash
./scripts/request-new-wallet.sh
```

Wait for DKG to complete, then verify:

```bash
./check-all-wallets-bridge.sh
```

The new wallet should show "Bridge State: Live ✅" instead of "Unknown".

### Step 4: Generate Deposit Data

```bash
./scripts/emulate-deposit.sh [depositor_address] [amount_satoshis]
```

Examples:
```bash
# Default: random depositor, 1 BTC
./scripts/emulate-deposit.sh

# Specify depositor and amount (0.5 BTC = 50000000 satoshis)
./scripts/emulate-deposit.sh 0x7966C178f466B060aAeb2B91e9149A5FB2Ec9c53 50000000
```

This generates:
- `deposit-data/deposit-data.json` - Complete deposit info
- `deposit-data/funding-tx-info.json` - BitcoinTxInfo for revealDeposit()
- `deposit-data/deposit-reveal-info.json` - DepositRevealInfo for revealDeposit()

### Step 5: Reveal Deposit to Bridge

**Using cast:**
```bash
BRIDGE=$(jq -r '.address' tmp/tbtc-v2/solidity/deployments/development/Bridge.json)
ACCOUNT=$(cast rpc eth_accounts --rpc-url http://localhost:8545 | jq -r '.[0]')

cast send "$BRIDGE" \
  "revealDeposit((bytes4,bytes,bytes,bytes4),(uint32,bytes8,bytes20,bytes20,bytes4,address))" \
  "$(cat deposit-data/funding-tx-info.json | jq -c .)" \
  "$(cat deposit-data/deposit-reveal-info.json | jq -c .)" \
  --rpc-url http://localhost:8545 \
  --from "$ACCOUNT" \
  --unlocked \
  --gas-limit 500000
```

**Or use the reveal script (update Bridge address first):**
```bash
# Update reveal-deposit.sh with full Bridge address
./reveal-deposit.sh
```

### Step 6: Monitor Deposit Events

```bash
BRIDGE=$(jq -r '.address' tmp/tbtc-v2/solidity/deployments/development/Bridge.json)

cast logs --from-block 0 --to-block latest \
  --address "$BRIDGE" \
  "DepositRevealed(bytes32,bytes32,address,uint256,bytes20,bytes20,uint32,bytes32)" \
  --rpc-url http://localhost:8545
```

### Step 7: Check Deposit Status

```bash
BRIDGE=$(jq -r '.address' tmp/tbtc-v2/solidity/deployments/development/Bridge.json)
DEPOSIT_KEY=$(cast keccak "$(cat deposit-data/deposit-data.json | jq -r '.fundingTxHash')$(cat deposit-data/deposit-data.json | jq -r '.fundingOutputIndex')")

cast call "$BRIDGE" "deposits(bytes32)" "$DEPOSIT_KEY" --rpc-url http://localhost:8545
```

## Option 2: Test Deposit Logic with Unit Tests (No Contracts Needed)

Test the deposit logic without deploying contracts:

```bash
# Test deposit script generation
go test -v ./pkg/tbtc -run TestDeposit_Script

# Test deposit sweep logic
go test -v ./pkg/tbtc -run TestDepositSweepAction_Execute

# Test deposit finding
go test -v ./pkg/tbtcpg -run TestDepositSweepTask_FindDepositsToSweep
```

## Option 3: Use Mock Bitcoin Chain (Advanced)

For full end-to-end testing with mock Bitcoin transactions:

```bash
# Setup mock Bitcoin chain
./setup-mock-bitcoin-chain.sh

# Generate deposit with mock Bitcoin transaction
./scripts/emulate-deposit.sh

# Monitor deposit events
./monitor-deposit-events.sh
```

## Quick Reference

### Check Wallet Status
```bash
./check-all-wallets-bridge.sh
```

### Check Specific Wallet
```bash
WALLET_PKH="0xfed577fbba8e72ec01810e12b09d974d7ef6b6bf"
BRIDGE=$(jq -r '.address' tmp/tbtc-v2/solidity/deployments/development/Bridge.json 2>/dev/null || echo "0xc0a2ee534F004a4ec2EFA541489acBD5ff4bBA99")

cast call "$BRIDGE" "wallets(bytes20)" "$WALLET_PKH" --rpc-url http://localhost:8545
```

### Wallet States
- **0**: Unknown (not registered in Bridge)
- **1**: Live ✅ (can accept deposits)
- **2**: MovingFunds
- **3**: Closing
- **4**: Closed
- **5**: Terminated

### Common Issues

**Issue**: "Bridge State: Unknown (00)"  
**Solution**: Bridge stub doesn't track wallets. Deploy full Bridge contract or use unit tests.

**Issue**: "revealDeposit() not found"  
**Solution**: Bridge stub doesn't implement this. Use full Bridge contract from `tmp/tbtc-v2`.

**Issue**: "Wallet not found in Bridge"  
**Solution**: Wallet was created before Bridge deployment. Create a new wallet after deploying Bridge.

## Next Steps After Deposit Reveal

1. **Operators detect deposit** - Wallet operators monitor for DepositRevealed events
2. **Create sweep proposal** - Operators create a proposal to sweep the deposit
3. **Sign and broadcast** - Operators sign and broadcast Bitcoin sweep transaction
4. **Mint tBTC** - After Bitcoin confirmations, tBTC tokens are minted to depositor

## Files Generated

- `deposit-data/deposit-data.json` - Complete deposit information
- `deposit-data/funding-tx-info.json` - BitcoinTxInfo structure
- `deposit-data/deposit-reveal-info.json` - DepositRevealInfo structure

## Additional Resources

- `DEPOSIT_SETUP_SUMMARY.md` - Deposit setup summary
- `deposit-processing-timeline.md` - Deposit processing timeline
- `scripts/emulate-deposit.sh` - Deposit data generation script
- `reveal-deposit.sh` - Deposit reveal script
