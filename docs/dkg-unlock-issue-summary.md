# DKG Approval Unlock Issue - Complete Summary

## Problem
`approveDkgResult()` transaction reverts when trying to unlock the sortition pool.

## Investigation Results

### Transaction Trace Analysis
Using `debug_traceCall`, we identified the exact failure point:

1. ✅ `approveResult()` - All checks passed (hash, state, timing)
2. ✅ `addWallet()` - Wallet created successfully
3. ✅ `WalletCreated` event - Emitted
4. ✅ `setRewardIneligibility()` - Executed (if needed)
5. ✅ `__ecdsaWalletCreatedCallback()` - Callback executed successfully
6. ❌ `dkg.complete() -> sortitionPool.unlock()` - **FAILED HERE**

### Root Cause

The `unlock()` function in `SortitionPool` requires `onlyOwner`:

```solidity
function unlock() public onlyOwner {
    isLocked = false;
}
```

When called from `dkg.complete()`:
- `dkg.complete()` is a library function called via DELEGATECALL
- Code executes in WalletRegistry's storage context ✅
- When library code calls `sortitionPool.unlock()` (external CALL):
  - **Issue**: `msg.sender` may be preserved from the original transaction sender
  - The `onlyOwner` modifier checks: `msg.sender == owner`
  - Since `msg.sender` = user account (not WalletRegistry), the check fails ❌

### Verification

- ✅ Pool is locked: `isLocked() = true`
- ✅ WalletRegistry is owner: `owner() = WalletRegistry.address`
- ✅ Static call succeeds: When called directly from WalletRegistry
- ❌ Transaction fails: When called from within library function

## Solution

Move the `unlock()` call from `EcdsaDkg.complete()` to `WalletRegistry.approveDkgResult()` so it's called directly by WalletRegistry (the owner).

### Code Changes Required

1. **Remove unlock() from EcdsaDkg.complete()**:
```solidity
function complete(Data storage self) internal {
    delete self.startBlock;
    delete self.seed;
    delete self.resultSubmissionStartBlockOffset;
    submittedResultCleanup(self);
    // REMOVED: self.sortitionPool.unlock();
}
```

2. **Add unlock() to WalletRegistry.approveDkgResult()**:
```solidity
function approveDkgResult(DKG.Result calldata dkgResult) external {
    // ... existing code ...
    dkg.complete();
    sortitionPool.unlock(); // ADDED: Call directly from WalletRegistry
    // ... rest of function ...
}
```

3. **Update other functions** that call `dkg.complete()`:
   - `notifyDkgTimeout()` - Add `sortitionPool.unlock()` after `dkg.notifyDkgTimeout()`
   - `notifySeedTimeout()` - Add `sortitionPool.unlock()` after `dkg.notifySeedTimeout()`

## Files Created

- `solidity/ecdsa/scripts/trace-approval-revert.ts` - Transaction tracing script
- `solidity/ecdsa/scripts/check-pool-lock-status.ts` - Pool state checking script
- `solidity/ecdsa/scripts/test-unlock-direct.ts` - Direct unlock test script
- `docs/dkg-approval-revert-root-cause.md` - Initial root cause analysis
- `docs/dkg-unlock-fix-proposal.md` - Detailed fix proposal
- `docs/dkg-unlock-issue-summary.md` - This summary

## Next Steps

1. Implement the fix by modifying:
   - `solidity/ecdsa/contracts/libraries/EcdsaDkg.sol` - Remove unlock() from complete()
   - `solidity/ecdsa/contracts/WalletRegistry.sol` - Add unlock() after dkg.complete()
   - Update `notifyDkgTimeout()` and `notifySeedTimeout()` similarly

2. Test the fix:
   - Verify `approveDkgResult()` succeeds
   - Verify pool is unlocked after approval
   - Verify other DKG completion paths still work

3. Consider if this affects other contracts:
   - Check if RandomBeacon has similar issues
   - Verify all DKG completion paths are fixed

