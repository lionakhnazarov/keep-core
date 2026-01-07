# DKG Approval Revert - Root Cause Identified

## Summary
The transaction trace reveals the exact revert point: **`sortitionPool.unlock()`** fails during `dkg.complete()`.

## Transaction Trace Analysis

Using `debug_traceCall`, we traced the approval transaction execution:

### Call Sequence:
1. ✅ **approveResult()** - Hash check passed, state check passed, timing check passed
2. ✅ **addWallet()** - Wallet added successfully
3. ✅ **WalletCreated event** - Event emitted
4. ✅ **setRewardIneligibility()** - Misbehaved members handled (if any)
5. ✅ **__ecdsaWalletCreatedCallback()** - BridgeStub callback executed successfully
6. ❌ **dkg.complete() -> sortitionPool.unlock()** - **FAILED HERE**

### Trace Details:
```
Call to: 0x88b2480f0014ed6789690c1c4f35fc230ef83458 (SortitionPool)
Function: unlock() (selector: 0xa69df4b5)
Error: "execution reverted"
```

## Root Cause

The revert occurs in `EcdsaDkg.complete()` at line 560:
```solidity
function complete(Data storage self) internal {
    delete self.startBlock;
    delete self.seed;
    delete self.resultSubmissionStartBlockOffset;
    submittedResultCleanup(self);
    self.sortitionPool.unlock();  // ← FAILS HERE
}
```

## Possible Causes

1. **Sortition Pool Not Locked**: The `unlock()` function might require the pool to be locked first
2. **Access Control**: The `unlock()` function might have access control restrictions
3. **State Mismatch**: The sortition pool might be in an unexpected state
4. **Permission Issue**: WalletRegistry might not have permission to unlock the pool

## Next Steps

1. **Check SortitionPool Contract**: Inspect the `unlock()` function implementation to see what checks it performs
2. **Check Pool State**: Verify if the sortition pool is actually locked before calling unlock
3. **Check Permissions**: Verify if WalletRegistry has permission to call unlock on the sortition pool
4. **Review SortitionPool ABI**: Check the exact function signature and requirements

## Files Created

- `solidity/ecdsa/scripts/trace-approval-revert.ts` - Transaction tracing script
- `docs/dkg-approval-revert-root-cause.md` - This document

## Verification

All other checks passed:
- ✅ Encoding matches submission
- ✅ Hash matches stored hash
- ✅ Timing is correct (challenge period ended)
- ✅ Callback executes successfully
- ❌ Only `unlock()` fails

This confirms the issue is specifically with the sortition pool unlock operation, not with the DKG result validation or approval logic.

