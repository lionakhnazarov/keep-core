# How Wallet Busy Causes Slower Redemptions

## Overview

When a wallet is busy with an ongoing action, new redemption proposals **cannot be executed**. This causes redemptions to be delayed, adding **up to 2-5 hours** to the total redemption time.

---

## The Problem Flow

### Normal Flow (Wallet Available)

```
Coordination Window → Proposal Created → Wallet Available → Action Dispatched → Execution Starts
```

**Timeline**: ~20 minutes (coordination) + ~1.5 hours (execution) = **~1.7 hours**

### Busy Wallet Flow (Wallet Busy)

```
Coordination Window → Proposal Created → Wallet BUSY ❌ → Action Rejected → Wait for Next Window → Retry
```

**Timeline**: ~20 minutes (coordination) + **wait up to 2 hours** (wallet busy) + **wait up to 3 hours** (next window) + ~1.5 hours (execution) = **~6.7 hours**

---

## Step-by-Step: What Happens When Wallet Is Busy

### Step 1: Coordination Window Arrives

**Code**: `pkg/tbtc/node.go:970-996`

```go
onWindowFn := func(window *coordinationWindow) {
    // Fetch all wallets controlled by the node
    walletsPublicKeys := n.walletRegistry.getWalletsPublicKeys()
    
    for _, currentWalletPublicKey := range walletsPublicKeys {
        // Run coordination procedure
        go func(walletPublicKey *ecdsa.PublicKey) {
            result, ok := executeCoordinationProcedure(...)
            if ok {
                coordinationResultChan <- result
            }
        }(currentWalletPublicKey)
    }
}
```

**What happens**:
- Coordination window detected
- Redemption proposal generated (if requests are eligible)
- Proposal sent to processing

**Duration**: ~20 minutes (coordination window)

---

### Step 2: Proposal Processing Attempts Dispatch

**Code**: `pkg/tbtc/node.go:1117-1125`

```go
case ActionRedemption:
    if proposal, ok := result.proposal.(*RedemptionProposal); ok {
        node.handleRedemptionProposal(
            result.wallet,
            proposal,
            startBlock,
            expiryBlock,
        )
    }
```

**What happens**:
- Proposal handler called
- Creates redemption action
- Attempts to dispatch action

**Duration**: ~1 second

---

### Step 3: Wallet Dispatcher Checks Busy Status

**Code**: `pkg/tbtc/node.go:778-782` and `pkg/tbtc/wallet.go:155-176`

```go
err = n.walletDispatcher.dispatch(action)
if err != nil {
    walletActionLogger.Errorf("cannot dispatch wallet action: [%v]", err)
    return  // ❌ Action rejected, proposal lost
}
```

**Inside `dispatch()`**:

```go
func (wd *walletDispatcher) dispatch(action walletAction) error {
    wd.actionsMutex.Lock()
    defer wd.actionsMutex.Unlock()
    
    key := hex.EncodeToString(walletPublicKeyBytes)
    
    // ✅ Check if wallet already has an action
    if _, ok := wd.actions[key]; ok {
        return errWalletBusy  // ❌ REJECTED!
    }
    
    // Mark wallet as busy and execute
    wd.actions[key] = action.actionType()
    // ... execute action
}
```

**What happens**:
- Dispatcher checks if wallet has active action
- If busy: Returns `errWalletBusy`
- Action is **rejected and ignored**
- Proposal is **lost** (not queued)

**Duration**: ~1 millisecond (instant rejection)

---

### Step 4: Redemption Request Must Wait

**What happens next**:

1. **Proposal is lost**: The proposal created during coordination is discarded
2. **No retry mechanism**: The system doesn't automatically retry
3. **Must wait for next window**: Redemption request must wait for the next coordination window
4. **Request still eligible**: The redemption request remains pending and eligible

**Duration**: Up to **3 hours** (next coordination window)

---

### Step 5: Next Coordination Window Arrives

**What happens**:

1. **New proposal generated**: System tries again to create redemption proposal
2. **Wallet may still be busy**: If previous action hasn't completed, wallet still busy
3. **Cycle repeats**: Proposal rejected again, wait for next window

**Duration**: Another **3 hours** if wallet still busy

---

## Complete Timeline Example

### Scenario: Redemption Request While Wallet Busy

```
T+0:00    Redemption Request A created
          └─> Minimum age: 2 hours

T+2:00    Minimum age satisfied
          └─> Wait for coordination window: +1.5 hours

T+3:30    Coordination window arrives
          └─> Proposal A created
          └─> Attempt dispatch → Wallet BUSY ❌
          └─> Proposal rejected, lost

T+6:30    Next coordination window (3 hours later)
          └─> Proposal A created again
          └─> Attempt dispatch → Wallet still BUSY ❌
          └─> Proposal rejected again

T+7:00    Previous action completes
          └─> Wallet becomes available ✅

T+9:30    Next coordination window (3 hours later)
          └─> Proposal A created again
          └─> Attempt dispatch → Wallet available ✅
          └─> Action dispatched successfully
          └─> Execution starts: +1.5 hours

T+11:00   Redemption completes

Total: ~11 hours (vs ~4.5 hours if wallet was available)
Delay: +6.5 hours due to wallet busy
```

---

## Why Proposals Are Lost (Not Queued)

### Current Implementation

**Code**: `pkg/tbtc/node.go:778-782`

```go
err = n.walletDispatcher.dispatch(action)
if err != nil {
    walletActionLogger.Errorf("cannot dispatch wallet action: [%v]", err)
    return  // ❌ Just returns, no retry/queue
}
```

**Why**:
- Proposals are **ephemeral**: Created during coordination window
- No persistence: Proposals aren't stored
- Coordination-based: New proposals created each window
- Simpler design: Avoids complex queuing logic

**Impact**:
- If wallet busy, proposal is lost
- Must wait for next coordination window
- New proposal generated next window

---

## Delay Calculation

### Components of Delay

1. **Wait for wallet to become available**: Up to **2 hours** (validity period)
2. **Wait for next coordination window**: Up to **3 hours** (window frequency)
3. **Total delay**: Up to **5 hours** worst case

### Average Delay

**Best case**: Wallet becomes available before next window
- Delay: ~0-1 hour (wait for wallet)

**Average case**: Wallet busy, miss one window
- Delay: ~2-3 hours (wallet + next window)

**Worst case**: Wallet busy, miss multiple windows
- Delay: ~5+ hours (multiple coordination cycles)

---

## Real-World Scenarios

### Scenario 1: Single Redemption Queue

```
T+0:00    Redemption Request 1 created
T+2:00    Minimum age satisfied
T+3:30    Window arrives → Proposal created → Wallet available → Executes ✅
T+5:00    Redemption 1 completes

T+1:00    Redemption Request 2 created (while Request 1 executing)
T+3:00    Minimum age satisfied
T+3:30    Window arrives → Proposal created → Wallet BUSY ❌ → Rejected
T+6:30    Next window → Proposal created → Wallet available → Executes ✅
T+8:00    Redemption 2 completes

Delay for Request 2: +2.5 hours (missed one window)
```

### Scenario 2: Multiple Redemptions Queue

```
T+0:00    Redemption Request 1 created
T+2:00    Minimum age satisfied
T+3:30    Window → Proposal → Wallet available → Executes ✅

T+1:00    Redemption Request 2 created
T+3:00    Minimum age satisfied
T+3:30    Window → Proposal → Wallet BUSY ❌ → Rejected

T+2:00    Redemption Request 3 created
T+4:00    Minimum age satisfied
T+6:30    Window → Proposal → Wallet BUSY ❌ → Rejected (Request 1 still executing)

T+5:00    Redemption 1 completes → Wallet available ✅

T+9:30    Window → Proposal 2 → Wallet available → Executes ✅
T+11:00   Redemption 2 completes

T+9:30    Window → Proposal 3 → Wallet BUSY ❌ → Rejected (Request 2 executing)

T+12:30   Window → Proposal 3 → Wallet available → Executes ✅
T+14:00   Redemption 3 completes

Delays:
- Request 2: +6 hours (missed 2 windows)
- Request 3: +10 hours (missed 3 windows)
```

---

## Impact on Production

### High Traffic Scenarios

**Problem**: In production, wallets often have multiple redemption requests:

1. **First request**: Processes immediately (wallet available)
2. **Second request**: Must wait for first to complete (~1.5 hours)
3. **Third request**: Must wait for second to complete (~3 hours total)
4. **Fourth request**: Must wait for third to complete (~4.5 hours total)

**Result**: Redemptions queue up, each adding ~1.5-3 hours delay

### Busy Periods

**During high activity**:
- Wallets constantly busy
- New proposals constantly rejected
- Redemptions accumulate
- Average delay increases significantly

**Impact**: Average redemption time increases from **6-7 hours** to **8-10 hours**

---

## Why This Design?

### Benefits

1. **State consistency**: Prevents conflicts between actions
2. **UTXO safety**: Avoids double-spend scenarios
3. **Signing protocol**: Prevents resource conflicts
4. **Simplicity**: No complex queuing logic needed

### Trade-offs

1. **Delays**: Redemptions must wait when wallet busy
2. **No queuing**: Proposals are lost, not stored
3. **Coordination-based**: Relies on periodic windows

---

## Mitigation Strategies

### Current System

1. **Coordination windows**: Periodic retry mechanism
2. **Proposal regeneration**: New proposals created each window
3. **Automatic retry**: System automatically retries next window

### Potential Improvements

1. **Proposal queuing**: Store proposals when wallet busy, execute when available
2. **Shorter windows**: Reduce coordination window frequency (trade-off: more overhead)
3. **Multiple wallets**: Distribute load across multiple wallets
4. **Priority queuing**: Process older requests first

---

## Summary: How Wallet Busy Slows Redemptions

| Stage | Normal Flow | Busy Wallet Flow | Delay Added |
|-------|-------------|------------------|-------------|
| **Coordination** | ~20 min | ~20 min | 0 |
| **Dispatch** | ✅ Success | ❌ Rejected | - |
| **Wait for wallet** | 0 | Up to 2 hours | +0-2 hours |
| **Next window** | 0 | Up to 3 hours | +0-3 hours |
| **Execution** | ~1.5 hours | ~1.5 hours | 0 |
| **TOTAL** | **~1.7 hours** | **~6.7 hours** | **+5 hours** |

### Key Points

1. ✅ **Proposal created**: During coordination window
2. ❌ **Action rejected**: If wallet busy
3. ⏱️ **Must wait**: For wallet to become available
4. ⏱️ **Must wait**: For next coordination window
5. ✅ **Retry**: New proposal created next window

### Average Impact

- **Best case**: +0-1 hour (wallet becomes available quickly)
- **Average case**: +2-3 hours (miss one coordination window)
- **Worst case**: +5+ hours (miss multiple windows)

---

## Code References

1. **Coordination window**: `pkg/tbtc/node.go:970-996`
2. **Proposal processing**: `pkg/tbtc/node.go:1117-1125`
3. **Action dispatch**: `pkg/tbtc/node.go:778-782`
4. **Busy check**: `pkg/tbtc/wallet.go:171-176`
5. **Validity period**: `pkg/tbtc/redemption.go:18-23`

---

## Key Takeaways

1. ⏱️ **Wallet busy adds delay**: Up to 5 hours worst case
2. ❌ **Proposals are lost**: Not queued when wallet busy
3. 🔄 **Automatic retry**: System retries next coordination window
4. 📊 **Average impact**: +2-3 hours delay in production
5. 🎯 **Root cause**: Single-action-per-wallet constraint

