# What Does "Proposal Valid for 600 Blocks" Mean?

## Overview

When a redemption proposal is created, it's **valid for 600 blocks** (~2 hours). This means the proposal **must be executed within 600 blocks** of when execution starts, or it becomes **invalid and cannot be completed**.

---

## Simple Explanation

Think of it like a **ticket with an expiration time**:
- ✅ **Valid**: Proposal can be executed
- ⏱️ **Time limit**: 600 blocks (~2 hours)
- ❌ **Expired**: Proposal becomes invalid, cannot be executed

---

## How Validity Works

### Step 1: Proposal Creation

**Code**: `pkg/tbtc/node.go:1095-1096`

```go
startBlock := result.window.endBlock()  // When execution can start
expiryBlock := startBlock + result.proposal.ValidityBlocks()  // When it expires
// For redemption: expiryBlock = startBlock + 600
```

**What happens**:
- Proposal created during coordination window
- `startBlock`: Block when execution can begin (end of coordination window)
- `expiryBlock`: Block when proposal expires (`startBlock + 600`)

**Example**:
```
Coordination window ends at block 1000
startBlock = 1000
expiryBlock = 1000 + 600 = 1600
Proposal valid from block 1000 to block 1600
```

---

### Step 2: Validity Period Calculation

**Code**: `pkg/tbtc/redemption.go:18-23`

```go
// redemptionProposalValidityBlocks determines the redemption proposal
// validity time expressed in blocks. In other words, this is the worst-case
// time for a redemption during which the wallet is busy and cannot take
// another actions. The value of 600 blocks is roughly 2 hours, assuming
// 12 seconds per block.
redemptionProposalValidityBlocks = 600
```

**Timeline**:
```
Block 1000: Proposal execution starts
           └─> Wallet marked as BUSY ✅
           └─> Validity period begins

Block 1000-1600: Validity period (600 blocks)
                 └─> Proposal can be executed
                 └─> Wallet stays BUSY

Block 1600: Proposal expires
            └─> Proposal becomes INVALID ❌
            └─> Wallet becomes available ✅
```

**Duration**: 600 blocks × 12 seconds/block = **7,200 seconds = 2 hours**

---

## What Happens During Validity Period

### Wallet Stays Busy

**Code**: `pkg/tbtc/wallet.go:178`

```go
// Mark wallet as busy for entire validity period
wd.actions[key] = action.actionType()
// Wallet stays busy until action completes OR validity expires
```

**What this means**:
- Wallet cannot process other actions
- Other proposals are rejected (`errWalletBusy`)
- Wallet locked for up to 600 blocks (~2 hours)

### Execution Must Complete

**Code**: `pkg/tbtc/redemption.go:233-238`

```go
redemptionTx, err := ra.transactionExecutor.signTransaction(
    signTxLogger,
    unsignedRedemptionTx,
    ra.proposalProcessingStartBlock,
    ra.proposalExpiryBlock - ra.signingTimeoutSafetyMarginBlocks,  // Deadline
)
```

**Signing deadline**:
- Must complete signing before: `expiryBlock - 300 blocks`
- Safety margin: 300 blocks reserved for post-signing steps
- Signing deadline: `1600 - 300 = block 1300`

**Timeline breakdown**:
```
Block 1000: Execution starts
Block 1000-1300: Signing phase (300 blocks max)
Block 1300-1600: Post-signing phase (300 blocks reserved)
                 └─> Broadcast transaction
                 └─> Wait for Bitcoin confirmation
                 └─> Submit SPV proof
Block 1600: Validity expires
```

---

## What Happens If Proposal Expires?

### Before Execution Starts

**If wallet is busy when proposal created**:
```go
err = n.walletDispatcher.dispatch(action)
if err != nil {
    // errWalletBusy - proposal rejected
    return  // Proposal lost, not executed
}
```

**Result**:
- Proposal is **rejected and lost**
- Must wait for next coordination window
- New proposal generated next window

### During Execution

**If execution takes too long**:

**Code**: `pkg/tbtc/redemption.go:229-231`

```go
// Just in case. This should never happen.
if ra.proposalExpiryBlock < ra.signingTimeoutSafetyMarginBlocks {
    return fmt.Errorf("invalid proposal expiry block")
}
```

**Safety mechanisms**:
- Signing deadline set before expiry (`expiryBlock - 300 blocks`)
- Ensures enough time for post-signing steps
- Prevents execution from running past expiry

**If somehow execution runs past expiry**:
- Proposal becomes invalid
- Execution should fail
- Wallet becomes available
- Redemption request remains pending (can retry next window)

---

## Why 600 Blocks?

### Worst-Case Time Budget

The 600 blocks represent the **worst-case time budget** for completing the entire redemption:

| Phase | Blocks | Time | Purpose |
|-------|--------|------|---------|
| **Signing** | 300 blocks | ~1 hour | Multi-party threshold signing |
| **Safety Margin** | 300 blocks | ~1 hour | Post-signing steps (broadcast, confirmation) |
| **TOTAL** | **600 blocks** | **~2 hours** | Complete redemption process |

### Safety Margins

**Code**: `pkg/tbtc/redemption.go:24-33`

```go
// redemptionSigningTimeoutSafetyMarginBlocks determines the duration of the
// safety margin that must be preserved between the signing timeout
// and the timeout of the entire redemption action. This safety
// margin prevents against the case where signing completes late and there
// is not enough time to broadcast the redemption transaction properly.
// In such a case, wallet signatures may leak and make the wallet subject
// of fraud accusations.
redemptionSigningTimeoutSafetyMarginBlocks = 300
```

**Why safety margin**:
- Prevents signature leaks if signing completes late
- Ensures enough time for broadcast and confirmation
- Protects against timing edge cases

---

## Real-World Example

### Successful Execution

```
Block 1000: Coordination window ends
            └─> Proposal created
            └─> startBlock = 1000
            └─> expiryBlock = 1600
            └─> Execution starts
            └─> Wallet BUSY ✅

Block 1000-1300: Signing phase
                 └─> Multi-party signing protocol
                 └─> Completes at block 1200 ✅

Block 1200-1300: Broadcast phase
                 └─> Broadcast transaction
                 └─> Completes at block 1250 ✅

Block 1250-1600: Bitcoin confirmation
                 └─> Wait for confirmations
                 └─> Completes at block 1400 ✅

Block 1400: Redemption completes
            └─> Wallet becomes available ✅
            └─> (Before expiry at block 1600)

Total: 400 blocks (~1.3 hours) - well within validity period
```

### Expired Proposal (Theoretical)

```
Block 1000: Proposal created
            └─> expiryBlock = 1600
            └─> Execution starts

Block 1000-1600: Execution in progress
                 └─> Signing takes longer than expected
                 └─> Still executing...

Block 1600: Validity expires ❌
            └─> Proposal becomes invalid
            └─> Execution should fail
            └─> Wallet becomes available
            └─> Redemption request remains pending

Result: Must retry in next coordination window
```

**Note**: This shouldn't happen due to safety margins, but if it does, the proposal expires and the wallet becomes available.

---

## Validity Period Breakdown

### For Redemption

| Component | Blocks | Time | Purpose |
|-----------|--------|------|---------|
| **Signing allocation** | 300 blocks | ~1 hour | Multi-party signing protocol |
| **Safety margin** | 300 blocks | ~1 hour | Post-signing steps |
| **TOTAL** | **600 blocks** | **~2 hours** | Complete validity period |

### For Other Actions

| Action Type | Validity Blocks | Time | Why Different |
|-------------|----------------|------|---------------|
| **Redemption** | 600 blocks | ~2 hours | Standard |
| **Deposit Sweep** | 1200 blocks | ~4 hours | Longer (more complex) |
| **Moving Funds** | 650 blocks | ~2.2 hours | Slightly longer (commitment wait) |
| **Moved Funds Sweep** | 600 blocks | ~2 hours | Standard |
| **Heartbeat** | 600 blocks | ~2 hours | Standard |

---

## Key Points

### 1. **Time Limit**

- Proposal **must be executed** within 600 blocks
- After expiry, proposal becomes **invalid**
- Cannot execute expired proposals

### 2. **Wallet Lock**

- Wallet stays **busy** for entire validity period
- Other actions **rejected** during this time
- Wallet becomes available when action completes OR validity expires

### 3. **Safety Margins**

- Signing deadline: `expiryBlock - 300 blocks`
- Ensures enough time for post-signing steps
- Prevents execution from running past expiry

### 4. **Execution Timeline**

```
startBlock (0 blocks)
    ↓
Signing phase (0-300 blocks)
    ↓
Safety margin (300-600 blocks)
    ↓
expiryBlock (600 blocks)
```

---

## Summary

| Aspect | Details |
|--------|---------|
| **Validity Period** | 600 blocks (~2 hours) |
| **Start Block** | End of coordination window |
| **Expiry Block** | `startBlock + 600` |
| **Purpose** | Worst-case time budget for execution |
| **Wallet Status** | BUSY for entire validity period |
| **Signing Deadline** | `expiryBlock - 300 blocks` |
| **Safety Margin** | 300 blocks reserved for post-signing |
| **If Expires** | Proposal invalid, wallet available, retry next window |

---

## Code References

1. **Validity calculation**: `pkg/tbtc/node.go:1095-1096`
2. **Validity constant**: `pkg/tbtc/redemption.go:18-23`
3. **Signing deadline**: `pkg/tbtc/redemption.go:233-238`
4. **Safety margin**: `pkg/tbtc/redemption.go:24-33`
5. **Wallet busy**: `pkg/tbtc/wallet.go:178`

---

## Key Takeaways

1. ✅ **600 blocks = ~2 hours**: Proposal validity period
2. ⏱️ **Time limit**: Must execute within validity period
3. 🔒 **Wallet locked**: Stays busy for entire validity period
4. 🛡️ **Safety margins**: Prevents execution from running past expiry
5. 🔄 **If expires**: Proposal invalid, retry next window

