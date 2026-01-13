# Why tBTC Redemptions Take So Long

## Overview

tBTC redemptions involve multiple sequential steps with built-in delays for security and coordination. The total time can range from **several hours to days**, depending on various factors.

## Key Timing Components

### 1. Redemption Request Minimum Age Delay

**Duration**: Variable (typically 0-24 hours, can be longer)

Before a redemption request can be included in a proposal, it must meet a **minimum age requirement**:

- **Default minimum age**: Configurable (typically 0 seconds for development, but can be set higher)
- **Redemption delay**: Can be set per redemption request via the redemption watchtower
- **Formula**: `minAge = max(requestMinAge, redemptionDelay)`

The system only processes redemption requests that are:
- Old enough: `RequestedAt <= (now - minAge)`
- Not expired: `RequestedAt >= (now - requestTimeout)`

**Code Reference**: `pkg/tbtcpg/redemptions.go:378-404`

### 2. Coordination Window Frequency

**Duration**: Every **900 blocks** (~3 hours at 12s/block)

Wallets check for redemption proposals during **coordination windows**:

- **Coordination frequency**: `900 blocks` (~3 hours)
- **Active phase**: `80 blocks` (~16 minutes) - communication allowed
- **Passive phase**: `20 blocks` (~4 minutes) - validation/preparation
- **Total window**: `100 blocks` (~20 minutes)

Redemption is checked **every coordination window** (it's a priority action), but other actions (deposit sweep, moving funds) are checked every 4 windows.

**Code Reference**: `pkg/tbtc/coordination.go:25-44`

### 3. Proposal Validity Period

**Duration**: **600 blocks** (~2 hours)

Once a redemption proposal is created, it has a validity period:

- **Proposal validity**: `600 blocks` (~2 hours at 12s/block)
- During this time, the wallet is "busy" and cannot process other actions
- This ensures there's enough time to complete the entire redemption process

**Code Reference**: `pkg/tbtc/redemption.go:18-23`

### 4. Signing Process

**Duration**: Up to **300 blocks** (~1 hour)

The signing process has a safety margin:

- **Signing timeout**: `proposalExpiryBlock - 300 blocks`
- **Safety margin**: `300 blocks` (~1 hour) reserved for post-signing steps
- This prevents signature leaks if signing completes late

**Code Reference**: `pkg/tbtc/redemption.go:24-33`

### 5. Transaction Broadcast

**Duration**: Up to **15 minutes** + **1 minute check delay**

After signing, the Bitcoin transaction must be broadcast:

- **Broadcast timeout**: `15 minutes` (25% of safety margin)
- **Broadcast check delay**: `1 minute` (network propagation time)
- Multiple retries allowed within the timeout window

**Code Reference**: `pkg/tbtc/redemption.go:34-48`

### 6. Bitcoin Network Confirmation

**Duration**: Variable (typically 10-60 minutes)

After broadcast, the transaction needs Bitcoin confirmations:

- **SPV proof requirement**: Typically 6 confirmations (~1 hour)
- **Network congestion**: Can add significant delays
- **Fee competition**: Low fees may delay inclusion

## Typical Timeline

### Best Case Scenario
1. **Request submitted** → Wait for minimum age (0-24h)
2. **Next coordination window** → Up to 3 hours
3. **Proposal created** → Within coordination window (~20 min)
4. **Signing** → Up to 1 hour
5. **Broadcast** → ~15 minutes
6. **Bitcoin confirmation** → ~1 hour

**Total: ~5-6 hours minimum** (if no delays)

### Worst Case Scenario
1. **Request submitted** → Wait for minimum age (24h+)
2. **Miss coordination window** → Wait up to 3 hours
3. **Wallet busy with other action** → Wait for next window
4. **Proposal validity** → 2 hours
5. **Signing delays** → Up to 1 hour
6. **Broadcast retries** → Up to 15 minutes
7. **Bitcoin network delays** → Hours to days

**Total: Can be days** in worst case

## Why These Delays Exist

### Security Reasons
1. **Fraud prevention**: Minimum age delays prevent front-running attacks
2. **Signature safety**: Safety margins prevent signature leaks
3. **Coordination reliability**: Window-based coordination ensures all operators are synchronized

### Operational Reasons
1. **Network propagation**: Bitcoin transactions need time to spread
2. **Confirmation requirements**: SPV proofs need Bitcoin confirmations
3. **Resource management**: Wallets can only handle one action at a time

## Factors Affecting Speed

### Can Speed Up Redemptions
- ✅ **Higher Bitcoin fees**: Faster inclusion in blocks
- ✅ **Lower network congestion**: Faster confirmations
- ✅ **Active wallet operators**: More coordination windows processed
- ✅ **Lower redemption delay**: Shorter minimum age requirement

### Can Slow Down Redemptions
- ❌ **High redemption delay**: Longer minimum age requirement
- ❌ **Wallet busy**: Processing other actions (deposits, moving funds)
- ❌ **Low Bitcoin fees**: Delayed inclusion in blocks
- ❌ **Network congestion**: Slow Bitcoin confirmations
- ❌ **Operator downtime**: Missed coordination windows

## Monitoring Redemptions

You can monitor redemption status using:

1. **tBTCscan**: https://tbtcscan.com/redeems
2. **On-chain events**: `RedemptionRequested`, `RedemptionProposalSubmitted`
3. **Node logs**: Check coordination window execution
4. **Metrics**: `redemption_coordination_delay_seconds`, `redemption_bitcoin_mempool_delay_seconds`

## Code Constants Summary

```go
// Coordination
coordinationFrequencyBlocks = 900          // ~3 hours
coordinationActivePhaseDurationBlocks = 80 // ~16 minutes
coordinationPassivePhaseDurationBlocks = 20 // ~4 minutes

// Redemption Proposal
redemptionProposalValidityBlocks = 600     // ~2 hours
redemptionSigningTimeoutSafetyMarginBlocks = 300 // ~1 hour
redemptionBroadcastTimeout = 15 * time.Minute
redemptionBroadcastCheckDelay = 1 * time.Minute

// Redemption Delay (configurable per request)
// Default: 0 seconds (can be set via redemption watchtower)
```

## References

- Coordination windows: `pkg/tbtc/coordination.go`
- Redemption timing: `pkg/tbtc/redemption.go`
- Redemption proposal generation: `pkg/tbtcpg/redemptions.go`
- Chain interface: `pkg/chain/ethereum/tbtc.go:2390-2409`

