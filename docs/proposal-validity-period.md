# Proposal Validity Period: Why Wallets Are "Busy"

## Overview

When a redemption proposal is created, it has a **validity period of 600 blocks (~2 hours)**. During this entire period, the wallet is marked as **"busy"** and cannot process any other actions.

## What "Busy" Means

### Code Implementation

**Location**: `pkg/tbtc/wallet.go:122-176`

```go
// walletDispatcher ensures only one action per wallet at a time
type walletDispatcher struct {
    actionsMutex sync.Mutex
    // actions tracks currently executing actions per wallet
    actions map[string]WalletActionType
}

func (wd *walletDispatcher) dispatch(action walletAction) error {
    wd.actionsMutex.Lock()
    defer wd.actionsMutex.Unlock()
    
    key := hex.EncodeToString(walletPublicKeyBytes)
    
    // Check if wallet already has an action in progress
    if _, ok := wd.actions[key]; ok {
        return errWalletBusy  // ❌ Reject new action
    }
    
    // Mark wallet as busy
    wd.actions[key] = action.actionType()
    
    // Execute action in goroutine
    go func() {
        defer func() {
            // Remove from busy map when done
            delete(wd.actions, key)
        }()
        action.execute()
    }()
}
```

**Key Point**: The wallet dispatcher maintains a **per-wallet action lock**. Only one action can be active per wallet at any time.

## Why 600 Blocks Validity Period?

### Worst-Case Time Budget

**Code**: `pkg/tbtc/redemption.go:18-23`

```go
// redemptionProposalValidityBlocks determines the redemption proposal
// validity time expressed in blocks. In other words, this is the worst-case
// time for a redemption during which the wallet is busy and cannot take
// another actions. The value of 600 blocks is roughly 2 hours, assuming
// 12 seconds per block.
redemptionProposalValidityBlocks = 600
```

The 600 blocks represent the **worst-case time budget** for completing the entire redemption process:

1. **Proposal validation** (~minutes)
2. **Transaction signing** (up to 300 blocks = ~1 hour)
3. **Transaction broadcast** (up to 15 minutes)
4. **Bitcoin confirmation** (~1 hour)
5. **Safety margins** (to prevent signature leaks)

### Timeline Breakdown

```
Block 0:    Proposal created
            └─> Wallet marked as BUSY
            └─> Validity expires at block 600

Block 0-300: Signing phase
             └─> Multi-party signing protocol
             └─> Safety margin: 300 blocks reserved for post-signing

Block 300-600: Post-signing phase
               └─> Broadcast transaction
               └─> Wait for Bitcoin confirmation
               └─> Submit SPV proof

Block 600:  Validity expires
            └─> Wallet becomes available again
            └─> Can process new actions
```

## Why Prevent Other Actions?

### 1. **State Consistency**

A wallet can only have **one Bitcoin transaction in flight** at a time:

```go
// pkg/tbtc/wallet.go:62-65
// walletDispatcher ensures only one action is executed by a wallet at
// a time. All possible activities of a created wallet must be represented
// by appropriate actions dispatched through this component.
```

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
if ra.proposalExpiryBlock < ra.signingTimeoutSafetyMarginBlocks {
    return fmt.Errorf("invalid proposal expiry block")
}

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

## What Actions Are Blocked?

When a wallet is busy with redemption, these actions are **rejected**:

1. **Other Redemptions** ❌
   - Cannot process multiple redemptions simultaneously
   - Must wait for current redemption to complete

2. **Deposit Sweeps** ❌
   - Cannot sweep deposits while redeeming
   - Would conflict with UTXO management

3. **Moving Funds** ❌
   - Cannot move funds during redemption
   - Wallet state must be stable

4. **Moved Funds Sweeps** ❌
   - Cannot sweep moved funds during redemption
   - Wallet is locked for the validity period

5. **Heartbeats** ❌
   - Cannot send heartbeats during active action
   - Wallet is focused on completing the action

**Exception**: The action that's currently running continues until completion.

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
    // When this completes, wallet is no longer busy
}()
```

The wallet becomes available when:
- ✅ Redemption transaction is broadcast
- ✅ Action execution completes (success or failure)
- ✅ `defer` function removes wallet from busy map

### Validity Expiry

Even if the action hasn't completed, the proposal expires at:
```
proposalExpiryBlock = proposalProcessingStartBlock + 600
```

After expiry:
- Proposal is no longer valid
- Action should complete or fail
- Wallet becomes available for new actions

## Real-World Example

### Scenario: Redemption in Progress

```
Block 1000: Redemption proposal created
            └─> Wallet marked BUSY
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

## Impact on Users

### For Redemption Requests

- **First request**: Processes immediately (if wallet available)
- **Subsequent requests**: Must wait until wallet is available
- **Wait time**: Up to 600 blocks (~2 hours) worst case

### For Other Actions

- **Deposit sweeps**: Delayed if redemption in progress
- **Moving funds**: Cannot start during redemption
- **New redemptions**: Queued until wallet available

## Summary

| Aspect | Details |
|--------|---------|
| **Validity Period** | 600 blocks (~2 hours) |
| **Purpose** | Worst-case time budget for action completion |
| **Busy Mechanism** | Per-wallet action lock in `walletDispatcher` |
| **Why Single Action** | State consistency, UTXO management, signing protocol |
| **Blocked Actions** | All other wallet actions (redemptions, sweeps, moves) |
| **When Available** | After action completes or validity expires |
| **Impact** | Subsequent actions must wait up to 2 hours |

## Code References

1. **Wallet Dispatcher**: `pkg/tbtc/wallet.go:122-222`
2. **Validity Period**: `pkg/tbtc/redemption.go:18-23`
3. **Action Execution**: `pkg/tbtc/redemption.go:160-259`
4. **Busy Check**: `pkg/tbtc/wallet.go:171-176`

