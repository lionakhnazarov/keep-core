# DKG Unlock Fix - Implementation Summary

## Changes Implemented

### 1. EcdsaDkg.complete() - Removed unlock() call

**File**: `solidity/ecdsa/contracts/libraries/EcdsaDkg.sol`

**Before**:
```solidity
function complete(Data storage self) internal {
    delete self.startBlock;
    delete self.seed;
    delete self.resultSubmissionStartBlockOffset;
    submittedResultCleanup(self);
    self.sortitionPool.unlock();
}
```

**After**:
```solidity
function complete(Data storage self) internal {
    delete self.startBlock;
    delete self.seed;
    delete self.resultSubmissionStartBlockOffset;
    submittedResultCleanup(self);
    // unlock() is called by WalletRegistry after complete() to ensure
    // msg.sender is WalletRegistry (the owner), not the original transaction sender
}
```

### 2. WalletRegistry.approveDkgResult() - Added unlock() call

**File**: `solidity/ecdsa/contracts/WalletRegistry.sol`

**Change**: Added `sortitionPool.unlock();` after `dkg.complete();`

```solidity
dkg.complete();

// Unlock sortition pool. Must be called directly from WalletRegistry
// (not from within the library) so msg.sender is WalletRegistry (the owner)
sortitionPool.unlock();
```

### 3. WalletRegistry.notifySeedTimeout() - Added unlock() call

**File**: `solidity/ecdsa/contracts/WalletRegistry.sol`

**Change**: Added `sortitionPool.unlock();` after `dkg.notifySeedTimeout();`

```solidity
dkg.notifySeedTimeout();

// Unlock sortition pool. Must be called directly from WalletRegistry
// (not from within the library) so msg.sender is WalletRegistry (the owner)
sortitionPool.unlock();
```

### 4. WalletRegistry.notifyDkgTimeout() - Added unlock() call

**File**: `solidity/ecdsa/contracts/WalletRegistry.sol`

**Change**: Added `sortitionPool.unlock();` after `dkg.notifyDkgTimeout();`

```solidity
dkg.notifyDkgTimeout();

// Unlock sortition pool. Must be called directly from WalletRegistry
// (not from within the library) so msg.sender is WalletRegistry (the owner)
sortitionPool.unlock();
```

## Why This Fix Works

When `unlock()` is called from within a library function (via DELEGATECALL), `msg.sender` may be preserved from the original transaction sender, causing the `onlyOwner` check to fail.

By calling `unlock()` directly from WalletRegistry (not from within the library), `msg.sender` is guaranteed to be WalletRegistry (the owner), satisfying the `onlyOwner` requirement.

## Testing

After deploying the updated contracts, test:
1. `approveDkgResult()` - Should now succeed
2. `notifyDkgTimeout()` - Should unlock pool after timeout
3. `notifySeedTimeout()` - Should unlock pool after seed timeout

## Compilation Status

✅ **Compilation successful** - All changes compile without errors.

