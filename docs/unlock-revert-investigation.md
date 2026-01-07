# SortitionPool.unlock() Revert Investigation

## Summary
The `approveDkgResult()` transaction is reverting, and based on previous investigation, the revert occurs at `sortitionPool.unlock()`. This document investigates why `unlock()` might be failing.

## SortitionPool.unlock() Implementation

From `solidity/ecdsa/node_modules/@keep-network/sortition-pools/contracts/SortitionPool.sol`:

```solidity
function unlock() public onlyOwner {
    isLocked = false;
}
```

**Requirements:**
- `onlyOwner` modifier - caller must be the contract owner
- No other checks or requirements

## Verification

✅ **Pool is locked**: Confirmed via `isLocked()` call  
✅ **WalletRegistry is owner**: Confirmed via `owner()` call  
✅ **Owner matches**: WalletRegistry address matches SortitionPool owner

## Call Sequence in approveDkgResult()

The `approveDkgResult()` function executes in this order:

1. `dkg.approveResult(dkgResult)` - Validates hash, returns misbehaved members
2. `wallets.addWallet(...)` - Adds wallet to registry
3. `emit WalletCreated(...)` - Emits event
4. `sortitionPool.setRewardIneligibility(...)` - If misbehaved members exist
5. `walletOwner.__ecdsaWalletCreatedCallback(...)` - **Callback to wallet owner**
6. `dkg.complete()` - Cleans up DKG state
7. `sortitionPool.unlock()` - **Unlocks the pool** ⚠️
8. `reimbursementPool.refund(...)` - Refunds gas

## Possible Failure Points

### 1. Hash Mismatch (Most Likely)
Even when using event data directly, the hash check in `dkg.approveResult()` might still fail:
- The `approveResult()` function checks: `keccak256(abi.encode(result)) == self.submittedResultHash`
- If this fails, the transaction reverts before reaching `unlock()`

**Status**: Previous investigation showed hash mismatch errors when using Go client. Hardhat script using event data should bypass this, but still reverts.

### 2. WalletOwner Callback Failure
The `walletOwner.__ecdsaWalletCreatedCallback()` is called before `unlock()`. If this callback reverts:
- The entire transaction reverts
- We never reach `unlock()`
- Error would be "execution reverted" without specific reason

**Status**: Need to verify if walletOwner is properly configured and can handle the callback.

### 3. SortitionPool.unlock() Requirements
The `unlock()` function itself has no special requirements beyond `onlyOwner`. However:
- If pool is already unlocked, `unlock()` still succeeds (just sets `isLocked = false`)
- No revert condition exists for already-unlocked pools

**Status**: Pool is confirmed locked, and WalletRegistry is confirmed owner.

## Current Status

**Latest Finding**: Transaction reverts with **no error message** (`data="0x"`). This indicates:
- A low-level revert (require without message, assertion failure, or out-of-gas)
- Not a custom error with a message string
- The revert happens before `unlock()` is reached

**Verified**:
- ✅ WalletOwner is properly configured and callback succeeds
- ✅ Pool is locked and WalletRegistry is owner
- ✅ Using event data directly (should bypass hash mismatch)

## Next Steps

1. **Trace transaction with debugger**: Use Hardhat's debugger or `cast run --trace` to see exact revert point
2. **Check gas limits**: Verify transaction has enough gas
3. **Test individual steps**: Try calling `dkg.approveResult()` separately to isolate the issue
4. **Check for assertion failures**: Look for any `assert()` statements that might fail

## Related Documents
- `docs/dkg-hash-mismatch-issue.md` - Hash mismatch root cause
- `docs/dkg-approval-revert-root-cause.md` - Initial revert investigation

