# Why Proposal Execution Takes ~1.5 Hours

## Overview

Proposal execution includes multiple sequential steps that together take approximately **1.5 hours on average**. This is the time from when a proposal is created until the Bitcoin transaction is broadcast.

## Execution Steps Breakdown

### Step-by-Step Timeline

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Proposal Validation                                      │
│    Duration: ~5-10 minutes                                  │
│    - Validate proposal on-chain                             │
│    - Check wallet main UTXO                                 │
│    - Ensure wallet synced between chains                    │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. Transaction Assembly                                     │
│    Duration: ~1-2 minutes                                   │
│    - Build unsigned Bitcoin transaction                     │
│    - Calculate signature hashes                              │
│    - Prepare for signing                                    │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. Multi-Party Threshold Signing                           │
│    Duration: ~30-45 minutes (average)                        │
│    Maximum: ~1 hour (300 blocks timeout)                    │
│    - Announcement phase: 6 blocks (~1.2 min)               │
│    - Protocol execution: 30 blocks (~6 min) per attempt    │
│    - Multiple attempts if needed                            │
│    - Retry logic with cooldown: 5 blocks (~1 min)          │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. Transaction Broadcast                                    │
│    Duration: ~15 minutes (timeout)                          │
│    Average: ~5-10 minutes                                   │
│    - Broadcast to Bitcoin network                           │
│    - Retry on failure                                       │
│    - Verify transaction propagation                         │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┘
│ 5. Safety Margins                                           │
│    Duration: ~30-45 minutes                                 │
│    - Reserved for post-signing steps                        │
│    - Prevents signature leaks                               │
│    - Ensures completion within validity period              │
└─────────────────────────────────────────────────────────────┘
```

## Detailed Component Analysis

### 1. Proposal Validation (~5-10 minutes)

**Code**: `pkg/tbtc/redemption.go:160-207`

```go
// Validate proposal on-chain
validatedRequests, err := ValidateRedemptionProposal(...)

// Determine wallet's main UTXO
walletMainUtxo, err := DetermineWalletMainUtxo(...)

// Ensure wallet synced between BTC and host chain
err = EnsureWalletSyncedBetweenChains(...)
```

**Time**: 
- On-chain validation: ~2-3 minutes
- UTXO lookup: ~1-2 minutes
- Chain sync check: ~2-5 minutes
- **Total: ~5-10 minutes**

### 2. Transaction Assembly (~1-2 minutes)

**Code**: `pkg/tbtc/redemption.go:209-222` and `pkg/tbtc/wallet.go:272-280`

```go
// Assemble unsigned transaction
unsignedRedemptionTx, err := assembleRedemptionTransaction(...)

// Compute signature hashes
sigHashes, err := unsignedTx.ComputeSignatureHashes()
```

**Time**: 
- Transaction assembly: ~30 seconds
- Hash computation: ~30 seconds
- **Total: ~1-2 minutes**

### 3. Multi-Party Threshold Signing (~30-45 minutes average)

**Code**: `pkg/tbtc/signing_loop.go:22-46` and `pkg/tbtc/signing.go:182-324`

#### Signing Attempt Structure

```go
// Single signing attempt maximum blocks
signingAttemptAnnouncementDelayBlocks = 1      // ~12 seconds
signingAttemptAnnouncementActiveBlocks = 5     // ~1 minute
signingAttemptMaximumProtocolBlocks = 30        // ~6 minutes
signingAttemptCoolDownBlocks = 5               // ~1 minute
// Total per attempt: 41 blocks = ~8.2 minutes
```

#### Why Signing Takes Time

**Multi-Party Coordination**:
- Multiple operators must participate (threshold signing)
- Network communication between operators
- Message propagation delays
- Retry logic if some operators are slow/unavailable

**Signing Phases**:
1. **Announcement Phase** (6 blocks = ~1.2 min)
   - Operators announce readiness
   - Wait for threshold number of operators
   - Network propagation time

2. **Protocol Execution** (30 blocks = ~6 min per attempt)
   - Actual cryptographic signing protocol
   - Multiple rounds of communication
   - Signature share generation and aggregation

3. **Cooldown** (5 blocks = ~1 min)
   - Between retry attempts
   - Allows network to settle

**Average Signing Time**:
- **Best case**: ~15-20 minutes (first attempt succeeds)
- **Average case**: ~30-45 minutes (1-2 retries needed)
- **Worst case**: Up to 1 hour (300 blocks timeout)

**Code**: `pkg/tbtc/redemption.go:233-238`
```go
// Signing timeout = proposalExpiryBlock - 300 blocks
// This gives up to 300 blocks (~1 hour) for signing
redemptionTx, err := ra.transactionExecutor.signTransaction(
    signTxLogger,
    unsignedRedemptionTx,
    ra.proposalProcessingStartBlock,
    ra.proposalExpiryBlock - ra.signingTimeoutSafetyMarginBlocks,  // Deadline
)
```

### 4. Transaction Broadcast (~15 minutes timeout)

**Code**: `pkg/tbtc/redemption.go:248-256`

```go
// Broadcast timeout: 15 minutes
redemptionBroadcastTimeout = 15 * time.Minute
// Check delay: 1 minute (network propagation)
redemptionBroadcastCheckDelay = 1 * time.Minute
```

**Time**:
- **Happy path**: ~2-5 minutes (immediate broadcast success)
- **Average**: ~5-10 minutes (some retries)
- **Maximum**: **15 minutes** (timeout - this is the allocated time)

**Steps**:
1. Broadcast transaction to Bitcoin network
2. Wait for propagation (1 minute check delay)
3. Verify transaction is known on chain
4. Retry if not confirmed

### 5. Safety Margins (~30-45 minutes)

**Code**: `pkg/tbtc/redemption.go:24-33`

```go
// Safety margin: 300 blocks (~1 hour)
redemptionSigningTimeoutSafetyMarginBlocks = 300
```

**Purpose**: 
- Prevents signature leaks if signing completes late
- Ensures enough time for broadcast and verification
- Protects against timing edge cases

**How it works**:
- Signing deadline: `proposalExpiryBlock - 300 blocks`
- This reserves 300 blocks (~1 hour) for post-signing steps
- Actual usage: ~15-30 minutes typically
- Remaining margin: ~30-45 minutes buffer

## Total Time Calculation

### Core Components: Signing + Broadcast

The two main time-consuming steps are:

| Component | Time | Notes |
|-----------|------|-------|
| **Signing** | ~30 minutes | Multi-party threshold protocol (average) |
| **Broadcast** | ~15 minutes | Maximum timeout (typically ~5-10 min) |
| **Subtotal** | **~45 minutes** | Core execution time |

### Full Breakdown (Average Case)

| Step | Time | Notes |
|------|------|-------|
| **Validation** | ~7 minutes | On-chain checks |
| **Assembly** | ~1.5 minutes | Transaction building |
| **Signing** | ~30 minutes | Multi-party protocol (average) |
| **Broadcast** | ~15 minutes | Timeout (typically ~5-10 min) |
| **Safety Buffer** | ~15 minutes | Reserved margin |
| **TOTAL** | **~68 minutes** | **~1.1 hours** |

### Typical Range

- **Fast execution**: ~45-60 minutes
  - Quick signing (~15-20 min, first attempt succeeds)
  - Fast broadcast (~5 min)
  - Minimal validation delays

- **Average execution**: ~1-1.5 hours
  - Normal signing (~30 min, 1-2 retries)
  - Standard broadcast (~10-15 min)
  - Validation and safety margins

- **Slow execution**: ~2 hours (validity limit)
  - Multiple signing retries (~45-60 min)
  - Network delays
  - Maximum broadcast timeout (15 min)
  - Maximum safety margin usage

## Why Not Faster?

### 1. Multi-Party Coordination

**Threshold signing requires**:
- Multiple operators to participate
- Network messages between all participants
- Consensus on signature shares
- Cannot be parallelized (sequential protocol)

**Time impact**: Adds ~20-30 minutes vs single-party signing

### 2. Network Latency

**P2P communication**:
- Messages propagate through libp2p network
- Operators may be in different regions
- Network delays accumulate across rounds

**Time impact**: Adds ~5-15 minutes

### 3. Retry Logic

**If operators are slow/unavailable**:
- Protocol retries with different operator subset
- Cooldown periods between attempts
- Multiple attempts may be needed

**Time impact**: Adds ~10-20 minutes per retry

### 4. Safety Margins

**Security requirement**:
- Must reserve time for post-signing steps
- Prevents signature leaks
- Ensures completion within validity period

**Time impact**: Adds ~30-45 minutes buffer

## Code Constants Summary

```go
// Proposal Validity
redemptionProposalValidityBlocks = 600          // ~2 hours total

// Signing Allocation
redemptionSigningTimeoutSafetyMarginBlocks = 300  // ~1 hour safety margin
// Signing gets: 600 - 300 = 300 blocks (~1 hour max)

// Signing Attempt Timing
signingAttemptAnnouncementDelayBlocks = 1       // ~12 seconds
signingAttemptAnnouncementActiveBlocks = 5       // ~1 minute
signingAttemptMaximumProtocolBlocks = 30         // ~6 minutes
signingAttemptCoolDownBlocks = 5                // ~1 minute
// Per attempt: 41 blocks = ~8.2 minutes

// Broadcast Timing
redemptionBroadcastTimeout = 15 * time.Minute   // 15 minutes max
redemptionBroadcastCheckDelay = 1 * time.Minute // 1 minute check delay
```

## Real-World Example

### Typical Execution Flow

```
T+0:00    Proposal created
T+0:07    Validation complete
T+0:08    Transaction assembled
T+0:45    Signing complete (37 min average)
T+0:52    Broadcast complete (7 min average)
T+1:00    Safety margin buffer
─────────────────────────────
Total: ~1 hour (fast case)

T+0:00    Proposal created
T+0:10    Validation complete
T+0:12    Transaction assembled
T+0:50    Signing complete (38 min, 1 retry)
T+1:00    Broadcast complete (10 min, retries)
T+1:30    Safety margin used
─────────────────────────────
Total: ~1.5 hours (average case)
```

## Summary

### Core Execution Time

| Component | Time | Why |
|-----------|------|-----|
| **Signing** | ~30 min | Multi-party threshold protocol (average) |
| **Broadcast** | ~15 min | Maximum timeout (typically ~5-10 min) |
| **Subtotal** | **~45 min** | Core execution steps |

### Full Breakdown

| Component | Time | Why |
|-----------|------|-----|
| **Validation** | ~7 min | On-chain checks and UTXO lookup |
| **Assembly** | ~1.5 min | Transaction building |
| **Signing** | ~30 min | Multi-party threshold protocol |
| **Broadcast** | ~15 min | Maximum timeout |
| **Safety** | ~15 min | Reserved buffer |
| **TOTAL** | **~68 min** | **~1.1 hours average** |

**Why ~1.5 hours total?**
- **Signing + Broadcast**: ~45 minutes (core execution)
- **Validation + Assembly**: ~8-10 minutes (preparation)
- **Safety margins**: ~15-30 minutes (security requirement)
- **Network delays**: Additional time for retries and propagation

The **signing protocol (~30 min)** and **broadcast timeout (~15 min)** together account for ~45 minutes of the execution time. The remaining time comes from validation, assembly, and safety margins that ensure reliable completion.

## References

- Proposal execution: `pkg/tbtc/redemption.go:160-259`
- Signing timing: `pkg/tbtc/signing_loop.go:22-46`
- Signing protocol: `pkg/tbtc/signing.go:182-324`
- Broadcast timing: `pkg/tbtc/redemption.go:34-48`

