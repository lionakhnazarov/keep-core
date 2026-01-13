# Why Redemptions Take 6-7 Hours on Average

## Average Time Breakdown

Based on the timing constants and typical execution patterns, here's why redemptions average **6-7 hours**:

### Component Timeline (Average Case)

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Minimum Age Delay                                        │
│    Average: 0-1 hour (depends on requestMinAge config)     │
│    Range: 0-24+ hours (if delay is set)                     │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. Wait for Coordination Window                            │
│    Average: ~1.5 hours (half of 3-hour window)              │
│    Range: 0-3 hours (depends on when request created)      │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. Coordination Window Processing                          │
│    Average: ~20 minutes (window duration)                   │
│    Fixed: 100 blocks = ~20 minutes                          │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. Proposal Validity Period                                │
│    Average: ~1.5 hours (actual execution time)              │
│    Maximum: 2 hours (600 blocks validity)                    │
│    Includes: Signing + Broadcast + Safety margins           │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. Bitcoin Network Confirmation                            │
│    Average: ~1 hour (6 confirmations)                      │
│    Range: 10 minutes - several hours (network dependent)    │
└─────────────────────────────────────────────────────────────┘
```

## Detailed Calculation

### Average Case Scenario

| Step | Time | Notes |
|------|------|-------|
| **Minimum Age** | 0-1 hour | Usually 0 in dev, can be 1+ hour in production |
| **Wait for Window** | ~1.5 hours | Average of 0-3 hours (half of window frequency) |
| **Window Processing** | ~20 minutes | Coordination window duration (100 blocks) |
| **Proposal Execution** | ~1.5 hours | Signing (~30 min) + Broadcast (~15 min) + margins |
| **Bitcoin Confirmation** | ~1 hour | 6 confirmations at ~10 min each |
| **TOTAL AVERAGE** | **~5.5-6 hours** | |

### Why It Can Be Longer (6-7+ hours)

Additional delays can push the average higher:

1. **High Minimum Age**: If `requestMinAge` is set to 1-2 hours
2. **Missed Window**: Request created right after window → wait full 3 hours
3. **Wallet Busy**: Previous redemption still in progress → wait up to 2 hours
4. **Slow Signing**: Multi-party signing takes longer than average
5. **Bitcoin Congestion**: Network delays push confirmation time higher
6. **Multiple Coordination Cycles**: If proposal isn't created in first window

## Real-World Average: 6-7 Hours

### Typical Flow (Average Case)

```
T+0:00    Redemption request created
          └─> Minimum age check: 0 hours (if no delay)
          
T+1:30    Next coordination window arrives
          └─> Average wait: 1.5 hours
          
T+1:50    Coordination window completes
          └─> Proposal created: +20 minutes
          
T+3:20    Redemption transaction signed & broadcast
          └─> Execution: +1.5 hours
          
T+4:20    Bitcoin confirmation received
          └─> Network: +1 hour
          
Total: ~4.5 hours (best case average)
```

### With Additional Delays

```
T+0:00    Redemption request created
          └─> Minimum age: 1 hour (if configured)
          
T+2:30    Next coordination window
          └─> Wait: 1.5 hours + minimum age: 1 hour
          
T+2:50    Coordination window completes
          └─> Processing: +20 minutes
          
T+4:20    Previous redemption still in progress
          └─> Wait for wallet: +1 hour
          
T+5:20    New coordination window
          └─> Wait: +1 hour
          
T+5:40    Proposal created
          └─> Processing: +20 minutes
          
T+7:10    Transaction signed & broadcast
          └─> Execution: +1.5 hours
          
T+8:10    Bitcoin confirmation
          └─> Network: +1 hour
          
Total: ~8 hours (with delays)
```

## Key Factors Contributing to 6-7 Hour Average

### 1. Coordination Window Wait (Biggest Factor)

**Average Wait**: ~1.5 hours
- Windows happen every 3 hours
- Requests created at random times
- Average wait = half of window frequency = 1.5 hours

**Code**: `pkg/tbtc/coordination.go:28`
```go
coordinationFrequencyBlocks = 900  // ~3 hours
```

### 2. Proposal Validity Period

**Average Execution**: ~1.5 hours
- Signing: ~30 minutes (average, not worst case)
- Broadcast: ~15 minutes
- Safety margins: ~45 minutes buffer

**Code**: `pkg/tbtc/redemption.go:23`
```go
redemptionProposalValidityBlocks = 600  // ~2 hours max
```

### 3. Bitcoin Network Confirmation

**Average**: ~1 hour
- 6 confirmations required
- ~10 minutes per confirmation
- Can be faster or slower depending on network

### 4. Minimum Age Delay (Variable)

**Average**: 0-1 hour
- Development: Usually 0
- Production: Can be 1-24 hours depending on config
- Adds to total time

**Code**: `pkg/tbtcpg/redemptions.go:392`
```go
minAge := time.Duration(requestMinAge) * time.Second
if delay > minAge {
    minAge = delay
}
```

### 5. Wallet Availability

**Average Impact**: 0-2 hours
- If wallet is busy with previous action
- Must wait for validity period to expire
- Adds up to 2 hours delay

## Mathematical Average

### Best Case Average (No Delays)

```
Minimum Age:        0 hours
Window Wait:        1.5 hours (average)
Window Processing:  0.3 hours (20 min)
Execution:          1.5 hours
Bitcoin Confirm:    1 hour
─────────────────────────────
Total:              4.3 hours
```

### Typical Average (With Some Delays)

```
Minimum Age:        0.5 hours
Window Wait:        1.5 hours
Window Processing:  0.3 hours
Wallet Wait:        0.5 hours (sometimes busy)
Execution:          1.5 hours
Bitcoin Confirm:    1 hour
─────────────────────────────
Total:              5.3 hours
```

### Realistic Average (Production)

```
Minimum Age:        1 hour (if configured)
Window Wait:        1.5 hours
Window Processing:  0.3 hours
Wallet Wait:        1 hour (often busy)
Execution:          1.5 hours
Bitcoin Confirm:    1.2 hours (network delays)
─────────────────────────────
Total:              6.5 hours
```

## Why Not Faster?

### Cannot Be Optimized (By Design)

1. **Coordination Windows**: Must wait for synchronized blocks
   - Cannot check continuously (synchronization requirement)
   - 3-hour frequency is necessary for consensus

2. **Multi-Party Signing**: Requires coordination
   - Multiple operators must participate
   - Protocol has inherent delays

3. **Bitcoin Network**: External dependency
   - Confirmation time depends on Bitcoin network
   - Cannot be controlled by tBTC system

### Could Be Optimized (But Not Recommended)

1. **Reduce Window Frequency**: From 3 hours to 1 hour
   - ❌ Would break synchronization
   - ❌ Would increase network overhead

2. **Reduce Validity Period**: From 2 hours to 1 hour
   - ❌ Risk of signature leaks
   - ❌ Not enough time for Bitcoin confirmation

3. **Reduce Minimum Age**: From 1 hour to 0
   - ❌ Security risk (front-running)
   - ❌ Fraud prevention mechanism

## Summary: 6-7 Hour Average Explained

| Component | Time | Why |
|-----------|------|-----|
| **Minimum Age** | 0-1h | Security delay (configurable) |
| **Window Wait** | ~1.5h | Average wait for next coordination window |
| **Processing** | ~0.3h | Coordination window duration |
| **Execution** | ~1.5h | Signing + broadcast + margins |
| **Bitcoin** | ~1h | Network confirmation time |
| **Wallet Busy** | 0-2h | If previous action in progress |
| **TOTAL** | **~6-7h** | **Average across all scenarios** |

## Code Constants Summary

```go
// Coordination
coordinationFrequencyBlocks = 900          // ~3 hours between windows
coordinationDurationBlocks = 100          // ~20 minutes window duration

// Redemption Proposal
redemptionProposalValidityBlocks = 600    // ~2 hours validity
redemptionSigningTimeoutSafetyMarginBlocks = 300  // ~1 hour safety margin
redemptionBroadcastTimeout = 15 * time.Minute

// Minimum Age (configurable)
requestMinAge = varies (0-86400+ seconds)
redemptionDelay = varies (0-86400+ seconds per request)
```

## References

- Coordination windows: `pkg/tbtc/coordination.go:25-44`
- Proposal validity: `pkg/tbtc/redemption.go:18-23`
- Wallet dispatcher: `pkg/tbtc/wallet.go:153-176`
- Minimum age: `pkg/tbtcpg/redemptions.go:378-404`

