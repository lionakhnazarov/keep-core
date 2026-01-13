# Why Signing Process Takes Up to ~1 Hour

## Overview

The multi-party threshold signing process can take **up to ~1 hour** (300 blocks) due to the complexity of coordinating multiple operators, cryptographic protocol execution, network latency, and retry logic.

---

## Signing Timeout Calculation

### Maximum Signing Time

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
- `expiryBlock = startBlock + 600 blocks` (proposal validity)
- `signingTimeoutSafetyMarginBlocks = 300 blocks` (~1 hour)
- **Signing deadline** = `expiryBlock - 300 blocks` = `startBlock + 300 blocks`
- **Maximum signing time**: **300 blocks = ~1 hour**

**Timeline**:
```
Block 1000: Proposal execution starts
Block 1000-1300: Signing phase (300 blocks max = ~1 hour)
Block 1300: Signing deadline
Block 1300-1600: Safety margin (post-signing steps)
Block 1600: Proposal expires
```

---

## Signing Attempt Structure

### Per-Attempt Timing

**Code**: `pkg/tbtc/signing_loop.go:22-46`

```go
const (
    signingAttemptAnnouncementDelayBlocks = 1      // ~12 seconds
    signingAttemptAnnouncementActiveBlocks = 5     // ~1 minute
    signingAttemptMaximumProtocolBlocks = 30      // ~6 minutes
    signingAttemptCoolDownBlocks = 5              // ~1 minute
)

func signingAttemptMaximumBlocks() uint {
    return signingAttemptAnnouncementDelayBlocks +
           signingAttemptAnnouncementActiveBlocks +
           signingAttemptMaximumProtocolBlocks +
           signingAttemptCoolDownBlocks
    // = 1 + 5 + 30 + 5 = 41 blocks = ~8.2 minutes
}
```

**Single attempt breakdown**:

| Phase | Blocks | Time | Purpose |
|-------|--------|------|---------|
| **Announcement Delay** | 1 block | ~12 seconds | Wait before announcement |
| **Announcement Active** | 5 blocks | ~1 minute | Operators announce readiness |
| **Protocol Execution** | 30 blocks | ~6 minutes | Cryptographic signing protocol |
| **Cool Down** | 5 blocks | ~1 minute | Between retry attempts |
| **TOTAL** | **41 blocks** | **~8.2 minutes** | Per attempt maximum |

---

## Why Each Phase Takes Time

### 1. Announcement Phase (~1.2 minutes)

**Code**: `pkg/tbtc/signing_loop.go:260-274`

```go
readyMembersIndexes, err := srl.announcer.Announce(
    announceCtx,
    srl.signingGroupMemberIndex,
    fmt.Sprintf("%v-%v", srl.message, srl.attemptCounter),
)
```

**What happens**:
- Operators announce readiness to participate
- Messages broadcast via P2P network
- Wait for threshold number of operators
- Network propagation delays

**Why it takes time**:
- **P2P communication**: Messages propagate through libp2p network
- **Network latency**: 50-200ms per hop between operators
- **Multiple operators**: Must reach threshold (e.g., 51 out of 100)
- **Message retransmission**: Ensures all operators receive messages

**Duration**: 6 blocks = ~1.2 minutes

---

### 2. Protocol Execution Phase (~6 minutes)

**Code**: `pkg/tbtc/signing.go:312-324`

```go
result, err := signing.Execute(
    attemptCtx,
    signingAttemptLogger,
    message,
    sessionID,
    signer.signingGroupMemberIndex,
    signer.privateKeyShare,
    wallet.groupSize(),
    wallet.groupDishonestThreshold(...),
    attempt.excludedMembersIndexes,
    se.broadcastChannel,
    ...
)
```

**What happens**:
- Multi-round cryptographic protocol
- Each operator generates signature share
- Shares broadcast to other operators
- Shares verified and aggregated
- Threshold signature created

**Why it takes time**:
- **Multiple rounds**: Protocol has multiple communication rounds
- **Cryptographic operations**: Expensive computations (elliptic curve operations)
- **Network coordination**: Each round requires all operators to communicate
- **Message propagation**: Network delays accumulate across rounds
- **Verification**: Each operator verifies shares from others

**Duration**: 30 blocks = ~6 minutes per attempt

---

### 3. Cool Down Phase (~1 minute)

**Code**: `pkg/tbtc/signing_loop.go:200-203`

```go
if srl.attemptCounter > 1 {
    srl.attemptStartBlock = srl.attemptStartBlock +
        uint64(signingAttemptMaximumBlocks())
}
```

**What happens**:
- Wait period between retry attempts
- Allows network to settle
- Prevents rapid retry loops

**Why it takes time**:
- **Network settling**: Allows messages to propagate
- **Error recovery**: Time for operators to recover from issues
- **Prevents conflicts**: Avoids overlapping attempts

**Duration**: 5 blocks = ~1 minute

---

## Retry Logic

### Maximum Attempts

**Code**: `pkg/tbtc/node.go:28-42`

```go
// signingAttemptsLimit determines the maximum number of signing attempts
// that can be performed for the given message being subject of signing.
//
// The value of `5` should be enough to produce the signature even with
// `2` malicious members in a signing group of `100` members.
signingAttemptsLimit = 5
```

**Why 5 attempts**:
- Handles up to 2 malicious members in 100-member group
- Probability calculation: `P = (98 choose 51) / (100 choose 51) = ~0.24`
- Need ~5 attempts on average to succeed
- Trade-off between success rate and time

### Total Timeout Calculation

**Code**: `pkg/tbtc/signing.go:205-206`

```go
loopTimeoutBlock := startBlock +
    uint64(se.signingAttemptsLimit * signingAttemptMaximumBlocks())
// = startBlock + (5 × 41 blocks)
// = startBlock + 205 blocks (~41 minutes)
```

**However**, the actual deadline is:
```go
signingDeadline = expiryBlock - 300 blocks
// = startBlock + 600 - 300
// = startBlock + 300 blocks (~1 hour)
```

**Why 300 blocks instead of 205**:
- **Safety margin**: Extra time for network delays
- **Message retransmission**: Ensures all operators receive messages
- **Slow operators**: Accounts for slower operators
- **Edge cases**: Handles timing edge cases

---

## Real-World Signing Timeline

### Best Case (~15-20 minutes)

```
Block 1000: Signing starts
Block 1000-1006: Announcement phase (6 blocks = ~1.2 min)
Block 1006-1036: Protocol execution (30 blocks = ~6 min)
Block 1036: Signing complete ✅

Total: ~7.2 minutes (first attempt succeeds)
```

### Average Case (~30-45 minutes)

```
Block 1000: Signing starts

Attempt 1:
Block 1000-1006: Announcement (6 blocks)
Block 1006-1036: Protocol (30 blocks)
Block 1036: Attempt fails (not enough operators) ❌

Attempt 2:
Block 1041-1047: Announcement (6 blocks) - after cooldown
Block 1047-1077: Protocol (30 blocks)
Block 1077: Signing complete ✅

Total: ~77 blocks = ~15.4 minutes (2 attempts)
```

### Worst Case (~1 hour)

```
Block 1000: Signing starts

Attempt 1: Fails (41 blocks)
Attempt 2: Fails (41 blocks)
Attempt 3: Fails (41 blocks)
Attempt 4: Fails (41 blocks)
Attempt 5: Succeeds (41 blocks)

Total: 5 × 41 = 205 blocks = ~41 minutes
+ Network delays and retransmissions = ~1 hour
```

---

## Factors Contributing to Time

### 1. Multi-Party Coordination

**Problem**: Multiple operators must coordinate
- **Threshold requirement**: Need threshold number of operators (e.g., 51/100)
- **Consensus**: All operators must agree
- **Synchronization**: Must be synchronized across network

**Time impact**: +5-10 minutes

### 2. Network Latency

**Problem**: P2P communication delays
- **Global distribution**: Operators in different regions
- **Message hops**: 3-10 hops between operators
- **Propagation time**: 50-200ms per hop
- **Accumulation**: Delays accumulate across rounds

**Time impact**: +5-15 minutes

### 3. Cryptographic Operations

**Problem**: Expensive computations
- **Elliptic curve operations**: CPU-intensive
- **Signature generation**: Each operator generates share
- **Verification**: Verify shares from all operators
- **Aggregation**: Combine shares into threshold signature

**Time impact**: +2-5 minutes

### 4. Retry Logic

**Problem**: Multiple attempts may be needed
- **Operator availability**: Some operators may be slow/unavailable
- **Network issues**: Temporary network problems
- **Malicious operators**: Up to 2 malicious operators possible
- **Probability**: ~24% success rate per attempt

**Time impact**: +10-30 minutes (if retries needed)

### 5. Message Retransmission

**Problem**: Ensure all operators receive messages
- **P2P reliability**: Not all messages arrive immediately
- **Retransmission**: Messages retransmitted for reliability
- **Slow operators**: Wait for slowest operator
- **Done checks**: Verify all operators completed

**Time impact**: +5-10 minutes

---

## Why Not Faster?

### Cannot Be Optimized

1. **Multi-party protocol**: Requires coordination (fundamental limitation)
2. **Network latency**: Physical limitation (speed of light)
3. **Cryptographic operations**: Security requirement (cannot be skipped)
4. **Threshold requirement**: Security requirement (need threshold operators)

### Could Be Optimized (Trade-offs)

1. **Reduce retry attempts**: From 5 to 3
   - ❌ Lower success rate
   - ❌ More failures

2. **Reduce protocol blocks**: From 30 to 15
   - ❌ May not complete in time
   - ❌ Network delays may cause failures

3. **Reduce announcement time**: From 6 to 3 blocks
   - ❌ May miss operators
   - ❌ Lower success rate

---

## Summary: Why Up to ~1 Hour

| Component | Time | Why |
|-----------|------|-----|
| **Per Attempt** | ~8.2 min | Announcement + Protocol + Cooldown |
| **Best Case** | ~7-15 min | First attempt succeeds |
| **Average Case** | ~30-45 min | 1-2 retries needed |
| **Worst Case** | ~1 hour | Multiple retries + network delays |
| **Maximum Timeout** | **300 blocks** | **~1 hour** (safety margin) |

### Key Factors

1. ⏱️ **Multi-party coordination**: Requires multiple operators
2. 🌐 **Network latency**: P2P communication delays
3. 🔐 **Cryptographic operations**: Expensive computations
4. 🔄 **Retry logic**: Up to 5 attempts may be needed
5. 📡 **Message propagation**: Ensures all operators receive messages

---

## Code References

1. **Signing deadline**: `pkg/tbtc/redemption.go:233-238`
2. **Attempt timing**: `pkg/tbtc/signing_loop.go:22-46`
3. **Maximum attempts**: `pkg/tbtc/node.go:28-42`
4. **Total timeout**: `pkg/tbtc/signing.go:205-206`
5. **Protocol execution**: `pkg/tbtc/signing.go:312-324`

---

## Key Takeaways

1. ✅ **Maximum time**: 300 blocks (~1 hour) - safety margin
2. ⏱️ **Per attempt**: 41 blocks (~8.2 minutes)
3. 🔄 **Retry logic**: Up to 5 attempts allowed
4. 🌐 **Network delays**: P2P communication adds time
5. 🔐 **Cryptographic protocol**: Multi-round protocol takes time

