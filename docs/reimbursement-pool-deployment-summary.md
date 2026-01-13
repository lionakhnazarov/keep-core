# ReimbursementPool Deployment Summary

## ✅ Completed

1. **Deployed ReimbursementPool**
   - Address: `0x5864c31C3581213aDB97e555585B1bfC034E0CD9`
   - Static Gas: 40,800
   - Max Gas Price: 500 Gwei
   - Balance: 10 ETH

2. **Authorized WalletRegistry**
   - WalletRegistry is now authorized to call `refund()` on the new ReimbursementPool
   - Transaction: `0x4bbee7e0e1e2d2d58cb10dc06e814e4aed24d8b9efd3a6345e82c731ea1f35df`

## ⚠️ Remaining Issue

**WalletRegistry still points to old ReimbursementPool address**

- Current: `0x1E2C06EEf15A4cD7fc9712267b55cB5337dCf75a` (no code)
- New: `0x5864c31C3581213aDB97e555585B1bfC034E0CD9` (deployed and funded)

## Solution Options

### Option 1: Update via Governance (Recommended for Production)

The WalletRegistry's ReimbursementPool can be updated through WalletRegistryGovernance:

```bash
# 1. Begin update (requires governance owner)
cast send 0x1bEf6019C28A61130c5c04f6b906A16C85397ceA \
  "beginReimbursementPoolUpdate(address)" \
  0x5864c31C3581213aDB97e555585B1bfC034E0CD9 \
  --from <governance_owner> \
  --rpc-url http://localhost:8545

# 2. Wait 60 seconds (governance delay)

# 3. Finalize update
cast send 0x1bEf6019C28A61130c5c04f6b906A16C85397ceA \
  "finalizeReimbursementPoolUpdate()" \
  --from <governance_owner> \
  --rpc-url http://localhost:8545
```

**Governance Owner**: `0x23d5975f6D72A57ba984886d3dF40Dca7f10ceca`
**Governance Delay**: 60 seconds

### Option 2: Update Deployment File (Development Only)

For local development, you can update the deployment file to point to the new address:

1. Update `solidity/ecdsa/deployments/development/ReimbursementPool.json` to use address `0x5864c31C3581213aDB97e555585B1bfC034E0CD9`
2. Redeploy WalletRegistry with the new ReimbursementPool address

### Option 3: Authorize Old Address (Quick Fix)

If you want to keep using the old address, deploy ReimbursementPool at that address:

```bash
# Deploy ReimbursementPool at the old address
# This requires using CREATE2 or deploying with specific nonce
```

## Verification

After updating, verify:

```bash
# Check WalletRegistry's ReimbursementPool
cast call 0xd49141e044801DEE237993deDf9684D59fafE2e6 \
  "reimbursementPool()(address)" \
  --rpc-url http://localhost:8545

# Should return: 0x5864c31C3581213aDB97e555585B1bfC034E0CD9

# Check authorization
cast call 0x5864c31C3581213aDB97e555585B1bfC034E0CD9 \
  "isAuthorized(address)(bool)" \
  0xd49141e044801DEE237993deDf9684D59fafE2e6 \
  --rpc-url http://localhost:8545

# Should return: true
```

## Root Cause Summary

The DKG approval was reverting because:
1. WalletRegistry calls `reimbursementPool.refund()` at the end of `approveDkgResult()`
2. The ReimbursementPool address (`0x1E2C06EEf15A4cD7fc9712267b55cB5337dCf75a`) had no code
3. Calling a non-existent contract reverts with empty error data (`0x`)

## Next Steps

1. Update WalletRegistry to use the new ReimbursementPool address (via governance or deployment update)
2. Test DKG approval again - it should now succeed
3. Monitor logs to confirm the approval completes successfully


