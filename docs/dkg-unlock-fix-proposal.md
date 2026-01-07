# Fix for DKG Approval Unlock Issue

## Problem
`approveDkgResult()` fails because `sortitionPool.unlock()` is called from within `dkg.complete()`, which executes via DELEGATECALL. In this context, `msg.sender` is the original transaction sender (not WalletRegistry), causing the `onlyOwner` check to fail.

## Root Cause

The `unlock()` function requires `onlyOwner`:
```solidity
function unlock() public onlyOwner {
    isLocked = false;
}
```

When called from `dkg.complete()`:
- Code executes in WalletRegistry's storage (via DELEGATECALL) ✅
- But `msg.sender` = original transaction sender (user account) ❌
- `onlyOwner` checks: `msg.sender == owner` → fails because user ≠ WalletRegistry

## Solution

Move the `unlock()` call from `EcdsaDkg.complete()` to `WalletRegistry.approveDkgResult()` so it's called directly by WalletRegistry (the owner).

### Step 1: Modify EcdsaDkg.complete()

Remove the unlock() call from the library:

```solidity
function complete(Data storage self) internal {
    delete self.startBlock;
    delete self.seed;
    delete self.resultSubmissionStartBlockOffset;
    submittedResultCleanup(self);
    // REMOVED: self.sortitionPool.unlock();
}
```

### Step 2: Modify WalletRegistry.approveDkgResult()

Add unlock() call after dkg.complete():

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

    dkg.complete();
    
    // ADDED: Unlock directly from WalletRegistry (msg.sender = WalletRegistry)
    sortitionPool.unlock();

    reimbursementPool.refund(
        _dkgResultSubmissionGas +
            (gasStart - gasleft()) +
            _dkgResultApprovalGasOffset,
        msg.sender
    );
}
```

### Step 3: Update Other Functions

Also update `notifyDkgTimeout()` and `notifySeedTimeout()` if they call `dkg.complete()`:

```solidity
function notifyDkgTimeout() external {
    uint256 gasStart = gasleft();

    dkg.notifyDkgTimeout(); // This calls complete() internally
    
    // ADDED: Unlock after timeout
    sortitionPool.unlock();

    reimbursementPool.refund(
        (gasStart - gasleft()) + _notifyDkgTimeoutGasOffset,
        msg.sender
    );
}

function notifySeedTimeout() external {
    uint256 gasStart = gasleft();

    dkg.notifySeedTimeout(); // This calls complete() internally
    
    // ADDED: Unlock after timeout
    sortitionPool.unlock();

    reimbursementPool.refund(
        (gasStart - gasleft()) + _notifySeedTimeoutGasOffset,
        msg.sender
    );
}
```

### Step 4: Update EcdsaDkg Library

Update `notifyDkgTimeout()` and `notifySeedTimeout()` in the library to not call unlock:

```solidity
function notifyDkgTimeout(Data storage self) internal {
    require(hasDkgTimedOut(self), "DKG has not timed out");

    emit DkgTimedOut();

    complete(self); // This will no longer call unlock()
}

function notifySeedTimeout(Data storage self) internal {
    require(hasSeedTimedOut(self), "Awaiting seed has not timed out");

    emit DkgSeedTimedOut();

    complete(self); // This will no longer call unlock()
}
```

## Testing

After applying the fix:
1. Verify `approveDkgResult()` succeeds
2. Verify `notifyDkgTimeout()` still works
3. Verify `notifySeedTimeout()` still works
4. Verify pool is unlocked after DKG completion

## Impact

This fix affects:
- `WalletRegistry.approveDkgResult()` - Will now succeed
- `WalletRegistry.notifyDkgTimeout()` - Needs unlock() added
- `WalletRegistry.notifySeedTimeout()` - Needs unlock() added
- `EcdsaDkg.complete()` - Remove unlock() call
- `EcdsaDkg.notifyDkgTimeout()` - No change needed (calls complete)
- `EcdsaDkg.notifySeedTimeout()` - No change needed (calls complete)

