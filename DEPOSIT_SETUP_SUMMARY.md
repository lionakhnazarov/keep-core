# Deposit Testing Setup Summary

## Current Situation

✅ **Bridge Contract Deployed**: `0xc7BC782Da1AAb7ee5985aC94C575f374FA4C75e5`
✅ **Deposit Data Generated**: Ready in `deposit-data/` directory  
✅ **Wallet Exists**: Registered in WalletRegistry

❌ **Issue**: Wallet was created BEFORE Bridge deployment
❌ **Issue**: Bridge is not set as walletOwner
❌ **Result**: Wallet state in Bridge is "Unknown" (0), needs to be "Live" (1)

## Why Deposits Fail

The error "Wallet must be in Live state" occurs because:
- Bridge contract tracks wallet state separately from WalletRegistry
- When a wallet is created, WalletRegistry calls `walletOwner.__ecdsaWalletCreatedCallback()`
- Bridge implements this callback and registers the wallet internally
- Your wallet was created before Bridge existed, so Bridge never received the callback

## Solutions

### Option 1: Create New Wallet (Recommended for Full Testing)

**Prerequisites**: Bridge must be set as walletOwner

1. **Set Bridge as walletOwner**:
   ```bash
   # Fund governance first
   GOVERNANCE="0x1bef6019c28a61130c5c04f6b906a16c85397cea"
   ACCOUNT=$(cast rpc eth_accounts --rpc-url http://localhost:8545 | jq -r '.[0]')
   cast send $GOVERNANCE --value $(cast --to-wei 1 ether) --rpc-url http://localhost:8545 --unlocked --from $ACCOUNT
   
   # Begin update
   BRIDGE="0xc7BC782Da1AAb7ee5985aC94C575f374FA4C75e5"
   WR_GOV="0x1bef6019c28a61130c5c04f6b906a16c85397cea"
   cast send $WR_GOV "beginWalletOwnerUpdate(address)" $BRIDGE \
     --rpc-url http://localhost:8545 --unlocked --from $GOVERNANCE
   
   # Wait 60 seconds, then finalize
   cast send $WR_GOV "finalizeWalletOwnerUpdate()" \
     --rpc-url http://localhost:8545 --unlocked --from $GOVERNANCE
   ```

2. **Request new wallet**:
   ```bash
   ./scripts/request-new-wallet.sh
   ```

3. **Wait for DKG** (check logs or use `./scripts/wait-for-dkg-completion.sh`)

4. **Verify wallet is Live in Bridge**:
   ```bash
   ./check-wallet-bridge-status.sh
   ```

5. **Generate new deposit data**:
   ```bash
   ./scripts/emulate-deposit.sh
   ```

6. **Reveal deposit**:
   ```bash
   ./reveal-deposit.sh
   ```

### Option 2: Use Unit Tests (Works Now!)

Test deposit logic without contract setup:

```bash
# Test deposit script generation
go test -v ./pkg/tbtc -run TestDeposit_Script

# Test deposit sweep action
go test -v ./pkg/tbtc -run TestDepositSweepAction_Execute

# Test deposit finding logic
go test -v ./pkg/tbtcpg -run TestDepositSweepTask_FindDepositsToSweep
```

### Option 3: Manual Bridge Registration (If Possible)

If you can modify Bridge contract or have admin access, you could manually register the wallet. However, `registerNewWallet` can only be called by WalletRegistry, so this isn't straightforward.

## Quick Reference

**Check wallet status**: `./check-wallet-bridge-status.sh`
**Generate deposit data**: `./scripts/emulate-deposit.sh`  
**Reveal deposit**: `./reveal-deposit.sh`
**Bridge address**: `0xc7BC782Da1AAb7ee5985aC94C575f374FA4C75e5`

## Wallet States

- **0**: Unknown (not registered in Bridge) ← Your current state
- **1**: Live ✅ (can accept deposits)
- **2**: MovingFunds
- **3**: Closing
- **4**: Closed
- **5**: Terminated

## Next Steps

1. **For quick testing**: Use unit tests (Option 2) - works immediately
2. **For full integration testing**: Set Bridge as walletOwner and create new wallet (Option 1)
3. **For production**: Ensure Bridge is deployed and set as walletOwner BEFORE creating wallets
