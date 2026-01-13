# Why We Wait for the Next Coordination Window

## The Core Issue

**Coordination windows are discrete, block-aligned events**, not continuous processes. Even though redemption is checked every window, you may still need to wait because:

1. **Windows happen at specific block numbers** (multiples of 900)
2. **Redemption requests can be created at ANY block** (not just window blocks)
3. **The system only checks during window blocks**

## How Coordination Windows Work

### Window Detection Logic

**Code**: `pkg/tbtc/coordination.go:122-153`

```go
func watchCoordinationWindows(
    ctx context.Context,
    watchBlocksFn func(ctx context.Context) <-chan uint64,
    onWindowFn func(window *coordinationWindow),
) {
    blocksChan := watchBlocksFn(ctx)
    var lastWindow *coordinationWindow

    for {
        select {
        case block := <-blocksChan:
            // Only trigger if block is a multiple of 900
            if window := newCoordinationWindow(block); window.index() > 0 {
                if window.isAfter(lastWindow) {
                    lastWindow = window
                    go onWindowFn(window)  // Check redemptions here
                }
            }
        case <-ctx.Done():
            return
        }
    }
}
```

### Window Index Calculation

**Code**: `pkg/tbtc/coordination.go:103-120`

```go
func (cw *coordinationWindow) index() uint64 {
    // Window only valid if block is a multiple of 900
    if cw.coordinationBlock % coordinationFrequencyBlocks == 0 {
        return cw.coordinationBlock / coordinationFrequencyBlocks
    }
    return 0  // Invalid window - not a coordination block
}
```

**Key Point**: Windows only exist at blocks that are multiples of 900:
- Block 900 → Window index 1 ✅
- Block 1800 → Window index 2 ✅
- Block 2700 → Window index 3 ✅
- Block 901 → Window index 0 ❌ (not a coordination window)
- Block 1799 → Window index 0 ❌ (not a coordination window)

## Timeline Example

```
Block 900:  ┌─────────────────────────────────┐
            │ Coordination Window #1           │
            │ - Checks for redemption requests │
            │ - Creates proposals              │
            └─────────────────────────────────┘
            
Block 901:  [Redemption request created here]
            ↓
            ⏳ Waiting...
            
Block 902-1799: [System is NOT checking redemptions]
                [Request exists but not processed]
                
Block 1800: ┌─────────────────────────────────┐
            │ Coordination Window #2           │
            │ - Checks for redemption requests │
            │ - Finds request from block 901   │
            │ - Creates proposal               │
            └─────────────────────────────────┘
```

## Why This Design?

### 1. **Synchronization Requirement**

All wallet operators need to coordinate at the **same time**:
- Leader selection is deterministic based on block hash
- All operators must agree on which block is the coordination block
- Random seed is derived from block hash (needs `coordinationSafeBlockShift`)

**Code**: `pkg/tbtc/coordination.go:44-48`
```go
// coordinationSafeBlockShift ensures the block hash is finalized
coordinationSafeBlockShift = 32
```

### 2. **Deterministic Leader Selection**

The leader is selected deterministically from the coordination seed:
- Seed comes from block hash at `coordinationBlock - 32`
- All operators compute the same seed
- All operators select the same leader
- This requires a **specific block number**, not "any time"

**Code**: `pkg/tbtc/coordination.go:496-555`

### 3. **Efficiency**

- Checking every block would be wasteful
- Most blocks don't have new redemption requests
- Batching checks every 900 blocks reduces overhead
- Operators can prepare in advance for the next window

### 4. **Network Consensus**

- All operators must agree on when coordination happens
- Block numbers are the only reliable synchronization mechanism
- Ethereum block time is predictable (~12 seconds)
- 900 blocks = ~3 hours (predictable interval)

## The Waiting Period

### Best Case Scenario
```
Block 899:  [Just before window]
Block 900:  [Window starts] → Request created → Processed immediately ✅
```

### Worst Case Scenario
```
Block 901:  [Just after window] → Request created
Block 902-1799: [Waiting period - up to 2 hours 59 minutes]
Block 1800: [Next window] → Request processed ✅
```

### Average Wait Time
```
Average wait = coordinationFrequencyBlocks / 2
             = 900 blocks / 2
             = 450 blocks
             = ~1.5 hours (at 12s/block)
```

## Why Not Check Continuously?

### ❌ Problems with Continuous Checking

1. **No synchronization**: Operators wouldn't know when to coordinate
2. **Leader selection chaos**: Different operators might select different leaders
3. **Race conditions**: Multiple operators might create conflicting proposals
4. **Network overhead**: Constant checking would be inefficient
5. **Determinism lost**: Random seed needs a specific block hash

### ✅ Benefits of Block-Aligned Windows

1. **Perfect synchronization**: All operators check at the same block
2. **Deterministic leadership**: Same leader selected by all operators
3. **No races**: Only one coordination per window
4. **Efficient**: Batch processing every 3 hours
5. **Predictable**: Users know when to expect processing

## Code Evidence

### Window Detection Only at Specific Blocks

```go
// pkg/tbtc/coordination.go:138
if window := newCoordinationWindow(block); window.index() > 0 {
    // Only executes if block % 900 == 0
    go onWindowFn(window)
}
```

### Redemption Checked Every Window

```go
// pkg/tbtc/coordination.go:571-573
// Redemption action is a priority action and should be checked on every
// coordination window.
actions = append(actions, ActionRedemption)
```

**But**: This only happens when `window.index() > 0`, which requires `block % 900 == 0`.

## Summary

| Aspect | Details |
|--------|---------|
| **Window Frequency** | Every 900 blocks (~3 hours) |
| **Window Blocks** | Multiples of 900 only (900, 1800, 2700...) |
| **Request Creation** | Can happen at ANY block |
| **Request Processing** | Only at coordination window blocks |
| **Why Wait** | Windows are discrete events, not continuous |
| **Average Wait** | ~1.5 hours (half of 3 hours) |
| **Max Wait** | ~3 hours (if request created right after window) |

## The Answer

**"Redemption is checked every window"** means:
- ✅ Every coordination window checks for redemptions
- ✅ Redemption is a priority action (checked every window, not every 4 windows)
- ✅ No windows are skipped for redemption checks

**"We may need to wait for the next one"** means:
- ⏳ Windows only happen at specific block numbers (multiples of 900)
- ⏳ If you create a request between windows, you wait until the next window block
- ⏳ This is by design for synchronization and determinism

The system is **event-driven** (triggered by specific blocks), not **time-driven** (triggered continuously).

