# Deposit Processing Timeline

## Overview
After a deposit is revealed, it goes through several stages before tBTC tokens are minted.

## Key Timing Parameters

### 1. Deposit Min Age
- **Purpose**: Minimum time a deposit must exist before it can be swept
- **Value**: Configurable in Bridge contract (currently: 0 seconds in dev)
- **Impact**: Deposits can be swept immediately if set to 0

### 2. Bitcoin Confirmations Required
- **Required**: 6 confirmations on Bitcoin chain
- **Time**: ~72 minutes (assuming 12 min/block on Bitcoin mainnet)
- **Note**: In local dev with mock Bitcoin, this may be simulated differently

### 3. Deposit Sweep Proposal Validity
- **Duration**: 1200 blocks (~4 hours assuming 12 sec/block on Ethereum)
- **Purpose**: Maximum time window for completing a deposit sweep

### 4. Signing Phase
- **Timeout**: Proposal expiry - 300 blocks (~1 hour safety margin)
- **Purpose**: Time for wallet operators to sign the sweep transaction

### 5. Broadcast Phase
- **Timeout**: 15 minutes
- **Check Delay**: 1 minute after broadcast
- **Purpose**: Time to broadcast sweep transaction to Bitcoin

## Typical Processing Flow

1. **Deposit Revealed** ✅ (Already done)
   - Time: Immediate
   - Status: DepositRevealed event emitted

2. **Deposit Detection** (Next step)
   - Time: Usually within minutes
   - Process: Wallet operators scan for DepositRevealed events
   - Status: Check node logs for "deposit" or "sweep" activity

3. **Deposit Maturity Check**
   - Time: Depends on depositMinAge (0 in dev = immediate)
   - Process: Verify deposit is old enough

4. **Bitcoin Confirmations**
   - Time: 6 confirmations required
   - Note: In local dev, this may be simulated/instant

5. **Sweep Proposal Creation**
   - Time: Usually within minutes after detection
   - Process: Coordination leader creates sweep proposal

6. **Transaction Signing**
   - Time: Up to ~3 hours (proposal validity - safety margin)
   - Process: Wallet operators sign the sweep transaction

7. **Transaction Broadcast**
   - Time: ~15 minutes
   - Process: Broadcast signed transaction to Bitcoin

8. **Bitcoin Confirmations**
   - Time: Additional confirmations on Bitcoin
   - Process: Wait for Bitcoin network to confirm

9. **tBTC Minting**
   - Time: After Bitcoin confirmations
   - Process: Bridge mints tBTC tokens to depositor

## Total Estimated Time

**In Production (Bitcoin Mainnet)**:
- Minimum: ~1-2 hours (if everything is fast)
- Typical: ~4-6 hours
- Maximum: Up to proposal validity period (~4 hours) + Bitcoin confirmations

**In Local Development**:
- Much faster due to:
  - Mock Bitcoin chain (instant confirmations)
  - No real network delays
  - depositMinAge = 0
- Typical: **5-30 minutes** depending on:
  - Node polling intervals
  - Proposal creation timing
  - Signing coordination

## Current Status Check

Run these commands to check current status:

```bash
# Check if deposit has been detected
tail -f logs/node1.log | grep -i "deposit\|sweep"

# Check for sweep proposals
./show-deposit-events.sh

# Monitor in real-time
./monitor-deposit-events.sh
```

## Factors Affecting Processing Time

1. **Node Configuration**: How often nodes poll for new deposits
2. **Wallet Operator Activity**: How quickly operators respond
3. **Network Conditions**: Bitcoin/Ethereum network delays
4. **Deposit Min Age**: If set > 0, adds delay
5. **Bitcoin Confirmations**: Real Bitcoin requires ~72 min for 6 confirmations
