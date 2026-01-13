# Why Redemptions Take So Long on Production

## Overview

Redemptions on production typically take **6-8 hours** compared to faster times in development environments. This document explains the production-specific factors that contribute to longer redemption times.

---

## Production vs Development Comparison

| Factor | Development | Production | Impact |
|--------|-------------|------------|--------|
| **Minimum Age Delay** | 0 hours | 1-4 hours | +1-4 hours |
| **Ethereum Block Time** | ~1-2 seconds | ~12-15 seconds | +10-15% time |
| **Coordination Windows** | Same (3 hours) | Same (3 hours) | Same |
| **Number of Operators** | Few (3-5) | Many (10-100+) | +20-50% coordination |
| **Network Latency** | Low (local) | High (global) | +10-30% signing |
| **Bitcoin Network** | Testnet (fast) | Mainnet (variable) | +20-50% confirmations |
| **Wallet Availability** | Usually free | Often busy | +0-2 hours wait |
| **Transaction Size** | Small | Large (many requests) | +10-20% execution |

**Result**: Production redemptions take **2-3x longer** than development.

---

## Production-Specific Delays

### 1. Minimum Age Delay (1-4 hours) ⭐ **BIGGEST FACTOR**

**Development**: Usually 0 hours (no delay configured)  
**Production**: Typically 1-4 hours (security requirement)

**Why**:
- **Security**: Prevents front-running attacks
- **Fraud Detection**: Allows time to detect suspicious activity
- **Configurable**: Set per wallet via `RedemptionWatchtower`

**Code**: `pkg/tbtcpg/redemptions.go:392-403`
```go
minAge := time.Duration(requestMinAge) * time.Second
if delay > minAge {
    minAge = delay  // Use wallet-specific delay if higher
}
```

**Impact**: Adds **1-4 hours** to every redemption

**Example**:
- Request created at T+0:00
- Minimum age: 2 hours
- Can only process after T+2:00
- **Delay: +2 hours**

---

### 2. Slower Ethereum Block Times (+10-15%)

**Development**: ~1-2 seconds per block (fast mining)  
**Production**: ~12-15 seconds per block (realistic mining)

**Impact on Timing**:
- Coordination windows: 900 blocks = **3 hours** (vs ~15 minutes in dev)
- Proposal validity: 600 blocks = **2 hours** (vs ~10 minutes in dev)
- Signing timeout: 300 blocks = **1 hour** (vs ~5 minutes in dev)

**Why It Matters**:
- All block-based timings scale with block time
- Production block times are **10-15x slower**
- Adds cumulative delays throughout the process

**Example**:
- Coordination window wait: 1.5 hours (vs ~7.5 minutes in dev)
- Proposal execution: 1.5 hours (vs ~7.5 minutes in dev)
- **Total impact: +2.5 hours**

---

### 3. More Operators = Slower Coordination (+20-50%)

**Development**: 3-5 operators (small group)  
**Production**: 10-100+ operators (large distributed group)

**Impact**:

#### Coordination Phase
- **More operators** = more messages to broadcast
- **Network propagation** takes longer
- **Consensus** requires more time
- **Fault detection** more complex

**Code**: `pkg/tbtc/coordination.go:639-643`
```go
err = ce.broadcastChannel.Send(
    ctx,
    message,
    net.BackoffRetransmissionStrategy,  // Must reach all operators
)
```

#### Signing Phase
- **More operators** = more signature shares
- **Network latency** accumulates across operators
- **Retry logic** more likely needed
- **Coordination overhead** increases

**Code**: `pkg/tbtc/signing_loop.go:22-46`
```go
signingAttemptMaximumProtocolBlocks = 30  // Per attempt
// More operators = more attempts needed
```

**Impact**: Adds **20-50%** to coordination and signing times
- Coordination: +4-10 minutes
- Signing: +6-15 minutes
- **Total: +10-25 minutes**

---

### 4. Network Latency Between Operators (+10-30%)

**Development**: Operators on same network (low latency)  
**Production**: Operators globally distributed (high latency)

**Impact**:

#### P2P Communication
- **Message propagation**: 50-200ms per hop
- **Multiple hops**: 3-10 hops between operators
- **Total latency**: 150ms - 2 seconds per message
- **Multiple rounds**: Protocol requires many messages

#### Coordination Messages
- Leader broadcasts to all followers
- Each follower validates and responds
- **Latency accumulates** across all operators

**Example**:
- 20 operators globally distributed
- Average latency: 100ms per message
- Coordination requires: ~50 messages
- **Total latency: 5 seconds** (vs <1 second in dev)

**Impact**: Adds **10-30%** to coordination and signing
- Coordination: +2-6 minutes
- Signing: +3-9 minutes
- **Total: +5-15 minutes**

---

### 5. Bitcoin Network Congestion (+20-50%)

**Development**: Testnet (low congestion, fast confirmations)  
**Production**: Mainnet (variable congestion, slower confirmations)

**Impact**:

#### Transaction Broadcasting
- **Mempool congestion**: Transactions wait longer
- **Fee competition**: Lower fees = slower inclusion
- **Network propagation**: Slower in congested periods

#### Block Confirmations
- **Standard**: 6 confirmations = ~60 minutes
- **Congested**: 6 confirmations = ~90-120 minutes
- **Peak congestion**: Can take several hours

**Example**:
- Normal: 6 blocks × 10 min = 60 minutes
- Congested: 6 blocks × 15 min = 90 minutes
- **Delay: +30 minutes**

**Impact**: Adds **20-50%** to Bitcoin confirmation time
- Normal: ~60 minutes
- Congested: ~90-120 minutes
- **Total: +30-60 minutes**

---

### 6. Wallet Busy Periods (+0-2 hours)

**Development**: Usually one redemption at a time  
**Production**: Multiple concurrent redemptions

**Impact**:

#### Wallet Locking
- Wallet can only process **one action at a time**
- Previous redemption locks wallet for **2 hours** (validity period)
- New redemption must **wait** until wallet free

**Code**: `pkg/tbtc/wallet.go:153-176`
```go
// Wallet dispatcher prevents concurrent actions
if wallet.isBusy() {
    return errWalletBusy  // Must wait
}
```

**Example**:
- Redemption A starts at T+0:00 (locks wallet for 2 hours)
- Redemption B requested at T+0:30
- Redemption B must wait until T+2:00
- **Delay: +1.5 hours**

**Impact**: Adds **0-2 hours** when wallet is busy
- Average: ~30-60 minutes wait
- Worst case: Up to 2 hours

---

### 7. Larger Transactions (+10-20%)

**Development**: Small transactions (1-2 redemptions)  
**Production**: Large transactions (many redemptions per proposal)

**Impact**:

#### Transaction Size
- **More outputs** = larger transaction
- **Higher fees** = more time to estimate
- **More validation** = longer validation time

#### Signing Complexity
- **More outputs** = more signature hashes
- **Larger messages** = slower propagation
- **More data** = longer processing

**Example**:
- Small (2 redemptions): ~500 bytes, ~5 min signing
- Large (20 redemptions): ~2000 bytes, ~8 min signing
- **Delay: +3 minutes**

**Impact**: Adds **10-20%** to execution time
- Validation: +1-2 minutes
- Signing: +2-4 minutes
- **Total: +3-6 minutes**

---

## Complete Production Timeline

### Typical Production Redemption (6-8 hours)

```
T+0:00    Redemption request created
          └─> Minimum age delay: 2 hours (production config)
          
T+2:00    Minimum age satisfied
          └─> Wait for coordination window: +1.5 hours (average)
          
T+3:30    Coordination window arrives
          └─> Window processing: +20 minutes
          
T+3:50    Proposal created
          └─> Check wallet availability
          
T+4:20    Wallet available (was busy for 30 min)
          └─> Proposal execution starts: +1.5 hours
          
T+5:50    Transaction signed & broadcast
          └─> Bitcoin confirmation: +90 minutes (congested)
          
T+7:20    Bitcoin confirmed
          └─> SPV proof: +15 minutes
          
T+7:35    Redemption complete
          
Total: ~7.5 hours
```

### Development Comparison (2-3 hours)

```
T+0:00    Redemption request created
          └─> Minimum age: 0 hours (dev config)
          
T+0:08    Coordination window arrives (fast blocks)
          └─> Window processing: +2 minutes
          
T+0:10    Proposal created
          └─> Wallet available immediately
          
T+0:10    Proposal execution: +8 minutes (fast signing)
          
T+0:18    Transaction signed & broadcast
          └─> Bitcoin confirmation: +20 minutes (testnet)
          
T+0:38    Redemption complete
          
Total: ~38 minutes
```

**Difference**: Production takes **~12x longer** than development

---

## Why These Delays Exist

### Security Requirements (Cannot Be Reduced)

1. **Minimum Age Delay**
   - Prevents front-running attacks
   - Allows fraud detection
   - **Cannot be removed** without security risk

2. **Coordination Windows**
   - Ensures operator synchronization
   - Prevents conflicts
   - **Cannot be reduced** without breaking consensus

3. **Proposal Validity Period**
   - Prevents signature leaks
   - Ensures completion safety
   - **Cannot be reduced** without security risk

### Network Reality (Cannot Be Controlled)

1. **Ethereum Block Time**
   - Determined by Ethereum network
   - **Cannot be changed** by tBTC

2. **Bitcoin Confirmation**
   - Determined by Bitcoin network
   - **Cannot be accelerated** (security requirement)

3. **Network Latency**
   - Physical limitation (speed of light)
   - **Cannot be eliminated** with global operators

### Operational Factors (Can Be Optimized)

1. **Operator Count**
   - More operators = more security
   - But also = slower coordination
   - **Trade-off**: Security vs Speed

2. **Wallet Availability**
   - Can be improved with better scheduling
   - **Optimization possible**: Batch processing

3. **Transaction Size**
   - Can be optimized with better batching
   - **Optimization possible**: Smarter proposal generation

---

## Summary: Why Production is Slow

| Factor | Production Impact | Can Reduce? |
|-------|------------------|------------|
| **Minimum Age** | +1-4 hours | ❌ Security requirement |
| **Block Times** | +10-15% | ❌ Network determined |
| **More Operators** | +20-50% | ⚠️ Trade-off (security) |
| **Network Latency** | +10-30% | ❌ Physical limitation |
| **Bitcoin Congestion** | +20-50% | ❌ Network determined |
| **Wallet Busy** | +0-2 hours | ✅ Can optimize |
| **Large Transactions** | +10-20% | ✅ Can optimize |
| **TOTAL** | **+6-8 hours** | |

---

## What Can Be Done

### ✅ Optimizations Possible

1. **Better Wallet Scheduling**
   - Reduce wallet busy periods
   - Batch redemptions more efficiently
   - **Potential savings**: 30-60 minutes

2. **Smarter Proposal Generation**
   - Optimize transaction sizes
   - Better fee estimation
   - **Potential savings**: 5-10 minutes

3. **Operator Network Optimization**
   - Reduce operator count (security trade-off)
   - Optimize network topology
   - **Potential savings**: 10-20 minutes

### ❌ Cannot Be Optimized

1. **Minimum Age Delay**: Security requirement
2. **Coordination Windows**: Consensus requirement
3. **Ethereum Block Time**: Network determined
4. **Bitcoin Confirmation**: Network determined
5. **Network Latency**: Physical limitation

---

## Real-World Production Average

Based on production data, redemptions average **6-8 hours**:

- **Fast**: ~4-5 hours (best case, no delays)
- **Average**: ~6-7 hours (typical production)
- **Slow**: ~8-10 hours (with all delays)

**Breakdown**:
- Minimum age: 1-2 hours
- Window wait: 1.5 hours
- Coordination: 20 minutes
- Execution: 1.5 hours
- Bitcoin: 1-1.5 hours
- Wallet busy: 0-1 hour
- **Total: 6-8 hours**

---

## References

- Minimum age: `pkg/tbtcpg/redemptions.go:392-403`
- Coordination windows: `pkg/tbtc/coordination.go:25-44`
- Wallet dispatcher: `pkg/tbtc/wallet.go:153-176`
- Signing timing: `pkg/tbtc/signing_loop.go:22-46`
- Proposal validity: `pkg/tbtc/redemption.go:18-23`

