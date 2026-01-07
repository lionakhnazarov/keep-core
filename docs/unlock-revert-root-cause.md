# Root Cause: sortitionPool.unlock() Revert

## Problem

The `approveDkgResult()` transaction reverts at `sortitionPool.unlock()` with no error message.

## Trace Evidence

From `cast call --trace`:
```
├─ [175598] 0xa1D026081e446c8929582CA007F451fE7E70E87C::approveDkgResult(...) [delegatecall]
│   ├─ ...
│   ├─ emit DkgResultApproved(...)
│   ├─ emit WalletCreated(...)
│   ├─ [261] 0xc0a2ee534F004a4ec2EFA541489acBD5ff4bBA99::__ecdsaWalletCreatedCallback(...)
│   ├─ [5422] 0x88b2480f0014ED6789690C1c4F35Fc230ef83458::unlock()
│   └─ ← [Revert] EvmError: Revert
```

## Root Cause

**`sortitionPool.unlock()` reverts because `msg.sender` is not the owner.**

### Details

1. **SortitionPool.unlock()** has `onlyOwner` modifier:
   ```solidity
   function unlock() public onlyOwner {
       isLocked = false;
   }
   ```

2. **`onlyOwner` checks**: `msg.sender == owner()`
   - `owner()` returns: `0xd49141e044801DEE237993deDf9684D59fafE2e6` (WalletRegistry)
   - `msg.sender` is: `0x7966C178f466B060aAeb2B91e9149A5FB2Ec9c53` (deployer account)

3. **The check fails**: `msg.sender != owner()` → revert

### Why This Happens

When `approveDkgResult()` is called:
- Transaction sender: `0x7966C178f466B060aAeb2B91e9149A5FB2Ec9c53` (deployer)
- `msg.sender` throughout execution: deployer account
- SortitionPool owner: WalletRegistry contract address

Even though `unlock()` is called from within WalletRegistry code, `msg.sender` is **always** the original transaction sender, not the contract itself.

### Code Location

In `WalletRegistry.sol`:
```solidity
function approveDkgResult(DKG.Result calldata dkgResult) external {
    // ...
    dkg.complete();
    
    // Unlock sortition pool. Must be called directly from WalletRegistry
    // (not from within the library) so msg.sender is WalletRegistry (the owner)
    sortitionPool.unlock();  // ← REVERTS HERE
    // ...
}
```

**The comment is incorrect** - `msg.sender` is NOT WalletRegistry, it's the transaction sender.

## Solution

The `unlock()` call needs to be made in a way where `msg.sender` is WalletRegistry. Options:

1. **Use a separate transaction** - Call `unlock()` directly from WalletRegistry in a separate transaction
2. **Modify SortitionPool** - Add a function that allows WalletRegistry to unlock (e.g., `unlockByRegistry()`)
3. **Change ownership model** - Make the deployer account the owner instead of WalletRegistry
4. **Use a proxy pattern** - Have WalletRegistry delegate the unlock call through a mechanism that preserves `msg.sender`

## Current Status

- ✅ All DKG approval conditions pass
- ✅ WalletCreated event emitted successfully
- ✅ Callback executed successfully
- ❌ `unlock()` reverts due to `onlyOwner` check failure

## Next Steps

1. Verify if this is a known issue in the codebase
2. Check if there's a workaround or fix already implemented
3. Consider implementing one of the solutions above

