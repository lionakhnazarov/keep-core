# What Does "Wallet Busy" Mean?

## Overview

**"Wallet Busy"** means a wallet is currently executing an action and cannot process any other actions until the current one completes. This is a **safety mechanism** to prevent conflicts and ensure state consistency.

---

## Simple Explanation

Think of a wallet like a **single-lane bridge**:
- ✅ **One action at a time** can cross
- ❌ **Other actions must wait** until the current one finishes
- ⏱️ **Wait time**: Up to 2 hours (for redemptions)

---

## Technical Implementation

### Code Location

**File**: `pkg/tbtc/wallet.go:122-176`

### How It Works

```go
// walletDispatcher tracks active actions per wallet
type walletDispatcher struct {
    actionsMutex sync.Mutex
    // Map: wallet public key -> action type
    actions map[string]WalletActionType
}

func (wd *walletDispatcher) dispatch(action walletAction) error {
    wd.actionsMutex.Lock()
    defer wd.actionsMutex.Unlock()
    
    key := hex.EncodeToString(walletPublicKeyBytes)
    
    // ✅ Check if wallet already has an action
    if _, ok := wd.actions[key]; ok {
        return errWalletBusy  // ❌ Reject - wallet is busy!
    }
    
    // ✅ Mark wallet as busy
    wd.actions[key] = action.actionType()
    
    // ✅ Execute action in background
    go func() {
        defer func() {
            // ✅ Remove from busy map when done
            delete(wd.actions, key)
        }()
        action.execute()
    }()
    
    return nil
}
```

**Key Points**:
1. **Per-wallet lock**: Each wallet has its own action lock
2. **Single action**: Only one action per wallet at a time
3. **Automatic release**: Wallet becomes available when action completes

---

## When Is a Wallet Busy?

A wallet becomes busy when **any action starts**:

### Actions That Make Wallet Busy

1. **Redemption** (`ActionRedemption`)
   - Duration: Up to **600 blocks (~2 hours)**
   - Code: `pkg/tbtc/redemption.go:18-23`

2. **Deposit Sweep** (`ActionDepositSweep`)
   - Duration: Up to **600 blocks (~2 hours)**
   - Code: `pkg/tbtc/deposit_sweep.go:18-23`

3. **Moving Funds** (`ActionMovingFunds`)
   - Duration: Up to **650 blocks (~2.2 hours)**
   - Code: `pkg/tbtc/moving_funds.go:17-24`

4. **Moved Funds Sweep** (`ActionMovedFundsSweep`)
   - Duration: Up to **600 blocks (~2 hours)**
   - Code: `pkg/tbtc/moved_funds_sweep.go:36-43`

5. **Heartbeat** (`ActionHeartbeat`)
   - Duration: Up to **600 blocks (~2 hours)**
   - Code: `pkg/tbtc/heartbeat.go:17-24`

---

## How Long Is a Wallet Busy?

### Redemption Example

**Validity Period**: 600 blocks (~2 hours)

```
Block 0:    Redemption proposal created
            └─> Wallet marked as BUSY ✅
            └─> Validity expires at block 600

Block 0-300: Signing phase
             └─> Multi-party signing protocol
             └─> Wallet still BUSY

Block 300-600: Post-signing phase
               └─> Broadcast transaction
               └─> Wait for Bitcoin confirmation
               └─> Wallet still BUSY

Block 600:  Validity expires
            └─> Wallet becomes available ✅
            └─> Can process new actions
```

**Actual Duration**:
- **Best case**: ~1 hour (action completes quickly)
- **Average case**: ~1.5 hours (normal execution)
- **Worst case**: ~2 hours (full validity period)

---

## What Happens When Wallet Is Busy?

### New Actions Are Rejected

```go
// When trying to dispatch a new action
if _, ok := wd.actions[key]; ok {
    // Wallet already has an action in progress
    return errWalletBusy  // ❌ Rejected!
}
```

### Actions That Are Blocked

When a wallet is busy with redemption, these actions **cannot start**:

1. ❌ **Other Redemptions**
   - Cannot process multiple redemptions simultaneously
   - Must wait for current redemption to complete

2. ❌ **Deposit Sweeps**
   - Cannot sweep deposits while redeeming
   - Would conflict with UTXO management

3. ❌ **Moving Funds**
   - Cannot move funds during redemption
   - Wallet state must be stable

4. ❌ **Moved Funds Sweeps**
   - Cannot sweep moved funds during redemption
   - Wallet is locked for the validity period

5. ❌ **Heartbeats**
   - Cannot send heartbeats during active action
   - Wallet is focused on completing the action

---

## Why Prevent Multiple Actions?

### 1. **State Consistency**

A wallet can only have **one Bitcoin transaction in flight** at a time:

**Problem if multiple actions allowed**:
- Redemption transaction might conflict with deposit sweep
- Moving funds might interfere with redemption
- Multiple Bitcoin transactions could create double-spend scenarios

### 2. **UTXO Management**

Bitcoin wallets manage UTXOs (Unspent Transaction Outputs):

- **Redemption**: Spends wallet's main UTXO
- **Deposit Sweep**: Spends deposit UTXOs
- **Moving Funds**: Spends wallet UTXO to move to new wallet

**Conflict**: If redemption and deposit sweep run simultaneously:
- Both might try to spend the same UTXO
- One transaction will fail
- Funds could be locked or lost

### 3. **Signing Protocol Constraints**

The threshold signing protocol requires coordination:

```go
// pkg/tbtc/node.go:67-70
// protocolLatch makes sure no expensive number generator operations are
// running when signing or generating a wallet key are executed.
protocolLatch *generator.ProtocolLatch
```

**Problem**:
- Multiple signing operations would compete for protocol resources
- Signing requires all operators to coordinate
- Parallel actions would create race conditions

### 4. **Proposal Expiry Protection**

The validity period ensures the proposal can be completed:

```go
// pkg/tbtc/redemption.go:229-237
redemptionTx, err := ra.transactionExecutor.signTransaction(
    signTxLogger,
    unsignedRedemptionTx,
    ra.proposalProcessingStartBlock,
    ra.proposalExpiryBlock - ra.signingTimeoutSafetyMarginBlocks,  // Deadline
)
```

**If another action started**:
- Might delay the redemption past expiry
- Proposal would become invalid
- Signatures might leak (security risk)

---

## Real-World Example

### Scenario: Redemption in Progress

```
Block 1000: Redemption proposal created
            └─> Wallet marked BUSY ✅
            └─> Validity: blocks 1000-1600

Block 1100: New redemption request arrives
            └─> System tries to dispatch
            └─> walletDispatcher.dispatch() called
            └─> Returns errWalletBusy ❌
            └─> Request queued for next coordination window

Block 1300: Redemption transaction signed
            └─> Wallet still BUSY (validity until block 1600)

Block 1400: Redemption transaction broadcast
            └─> Wallet still BUSY

Block 1500: Bitcoin confirmation received
            └─> Redemption completes
            └─> Wallet becomes available ✅

Block 1600: Validity period expires
            └─> (Wallet already available from block 1500)
```

**Timeline**:
- **Busy from**: Block 1000
- **Available at**: Block 1500 (or block 1600 worst case)
- **Duration**: ~500 blocks (~1.7 hours)

---

## Impact on Users

### For Redemption Requests

- **First request**: Processes immediately (if wallet available)
- **Subsequent requests**: Must wait until wallet is available
- **Wait time**: Up to 600 blocks (~2 hours) worst case

### For Other Actions

- **Deposit sweeps**: Delayed if redemption in progress
- **Moving funds**: Cannot start during redemption
- **New redemptions**: Queued until wallet available

---

## When Does "Busy" End?

### Normal Completion

```go
// pkg/tbtc/wallet.go:189-202
go func() {
    defer func() {
        wd.actionsMutex.Lock()
        delete(wd.actions, key)  // ✅ Remove from busy map
        wd.actionsMutex.Unlock()
    }()
    
    err := action.execute()  // Execute redemption
    // When this completes, wallet is no longer busy ✅
}()
```

The wallet becomes available when:
- ✅ Action execution completes (success or failure)
- ✅ `defer` function removes wallet from busy map
- ✅ Wallet can now accept new actions

### Validity Expiry

Even if the action hasn't completed, the proposal expires at:
```
proposalExpiryBlock = proposalProcessingStartBlock + 600
```

After expiry:
- Proposal is no longer valid
- Action should complete or fail
- Wallet becomes available for new actions

---

## Summary

| Aspect | Details |
|--------|---------|
| **What It Means** | Wallet is executing an action and cannot process others |
| **Mechanism** | Per-wallet action lock in `walletDispatcher` |
| **Duration** | Up to 600 blocks (~2 hours) for redemptions |
| **Why Single Action** | State consistency, UTXO management, signing protocol |
| **Blocked Actions** | All other wallet actions (redemptions, sweeps, moves) |
| **When Available** | After action completes or validity expires |
| **Impact** | Subsequent actions must wait up to 2 hours |

---

## Code References

1. **Wallet Dispatcher**: `pkg/tbtc/wallet.go:122-222`
2. **Busy Check**: `pkg/tbtc/wallet.go:171-176`
3. **Validity Period**: `pkg/tbtc/redemption.go:18-23`
4. **Action Execution**: `pkg/tbtc/redemption.go:160-259`

---

## Key Takeaways

1. ✅ **One action per wallet**: Only one action can run at a time
2. ⏱️ **Up to 2 hours**: Wallet stays busy for the validity period
3. ❌ **Other actions rejected**: New actions must wait
4. 🔒 **Safety mechanism**: Prevents conflicts and state issues
5. ✅ **Automatic release**: Wallet becomes available when action completes

