# DKG Approval Unlock Issue - Root Cause

## Problem
The `approveDkgResult()` transaction reverts when trying to unlock the sortition pool.

## Root Cause

The `unlock()` function in `SortitionPool` has an `onlyOwner` modifier:

```solidity
function unlock() public onlyOwner {
    isLocked = false;
}
```

When `dkg.complete()` calls `self.sortitionPool.unlock()`, it's executing within a DELEGATECALL context from the DKG library. In a DELEGATECALL:

- The code executes in WalletRegistry's storage context ✅
- BUT `msg.sender` remains the **original transaction sender** (the account calling `approveDkgResult()`) ❌
- The `onlyOwner` modifier checks if `msg.sender == owner`, not if the calling contract is the owner

So when a regular account calls `approveDkgResult()`, `msg.sender` in `unlock()` is that account, not WalletRegistry (the owner), causing the revert.

## Call Flow

```
User Account (msg.sender = User)
  ↓
WalletRegistry.approveDkgResult()
  ↓
dkg.approveResult() [DELEGATECALL to library]
  ↓
... (other operations succeed)
  ↓
dkg.complete() [DELEGATECALL continues]
  ↓
sortitionPool.unlock() [msg.sender = User, not WalletRegistry]
  ↓
onlyOwner modifier checks: User == Owner? ❌ REVERT
```

## Solution

The `unlock()` call should be made directly by WalletRegistry after `dkg.complete()`, not from within the library's `complete()` function. This way, `msg.sender` will be WalletRegistry (the owner).

### Proposed Fix

Modify `WalletRegistry.approveDkgResult()` to call `unlock()` directly:

```solidity
function approveDkgResult(DKG.Result calldata dkgResult) external {
    uint256 gasStart = gasleft();
    uint32[] memory misbehavedMembers = dkg.approveResult(dkgResult);

    (bytes32 walletID, bytes32 publicKeyX, bytes32 publicKeyY) = wallets
        .addWallet(dkgResult.membersHash, dkgResult.groupPubKey);

    emit WalletCreated(walletID, keccak256(abi.encode(dkgResult)));

    if (misbehavedMembers.length > 0) {
        sortitionPool.setRewardIneligibility(
            misbehavedMembers,
            block.timestamp + _sortitionPoolRewardsBanDuration
        );
    }

    walletOwner.__ecdsaWalletCreatedCallback(
        walletID,
        publicKeyX,
        publicKeyY
    );

    // Complete DKG (but don't unlock here)
    dkg.completeWithoutUnlock(); // New function that doesn't call unlock()
    
    // Unlock directly from WalletRegistry (msg.sender = WalletRegistry)
    sortitionPool.unlock();

    reimbursementPool.refund(
        _dkgResultSubmissionGas +
            (gasStart - gasleft()) +
            _dkgResultApprovalGasOffset,
        msg.sender
    );
}
```

And modify `EcdsaDkg.complete()` to not call unlock:

```solidity
function complete(Data storage self) internal {
    delete self.startBlock;
    delete self.seed;
    delete self.resultSubmissionStartBlockOffset;
    submittedResultCleanup(self);
    // Remove: self.sortitionPool.unlock();
}
```

## Verification

- ✅ Pool is locked: Confirmed via `isLocked()`
- ✅ WalletRegistry is owner: Confirmed via `owner()`
- ✅ Static call succeeds: When called directly from WalletRegistry
- ❌ Transaction fails: When called from within DELEGATECALL context

## Impact

This affects all DKG completion paths:
- `approveDkgResult()` - Currently broken
- `notifyDkgTimeout()` - Likely also broken
- `notifySeedTimeout()` - Likely also broken

All of these call `dkg.complete()` which tries to unlock the pool, but fails due to the `msg.sender` issue.

