# DKG Failure Causes

This document outlines the primary causes of Distributed Key Generation (DKG) failures in the Keep Client.

## 1. **Attempt Limit Reached**

**Cause**: The DKG protocol exceeded the maximum number of retry attempts.

**Details**:
- The `dkgAttemptsLimit` constant in `pkg/tbtc/dkg.go` controls how many retry attempts are allowed
- Default was `1` (now increased to `3` for development)
- When all attempts fail, DKG aborts with: `"reached the limit of attempts [N]"`

**Error Message**:
```
failed to execute DKG: [reached the limit of attempts [1]]
```

**Fix**:
- Ensure nodes are running the latest binary with `dkgAttemptsLimit = 3`
- Rebuild and restart nodes after code changes

## 2. **Context Cancellation (Timeout)**

**Cause**: The DKG context is canceled when a timeout block is reached.

**Details**:
- DKG has two timeout mechanisms:
  1. **Overall DKG timeout**: `startBlock + SubmissionTimeoutBlocks` (from chain parameters)
  2. **Per-attempt timeout**: `announcementEndBlock + dkgAttemptMaximumProtocolBlocks` (1200 blocks)
- When the timeout block is reached, `withCancelOnBlock()` cancels the context
- This causes all DKG operations to abort with `context.Canceled`

**Error Message**:
```
dkg attempt failed: [context canceled]
```

**Timeout Calculation**:
```go
dkgTimeoutBlock := startBlock + dkgParameters.SubmissionTimeoutBlocks
```

**Fix**:
- Increase `SubmissionTimeoutBlocks` in contract parameters (via governance)
- Increase `dkgAttemptMaximumProtocolBlocks` in code (currently 1200 blocks)
- Ensure sufficient block time for DKG completion

## 3. **TSS Pre-Parameters Generation Timeout**

**Cause**: Cryptographic pre-parameters (Paillier keys, safe primes) take too long to generate.

**Details**:
- DKG requires CPU-intensive cryptographic computations:
  - **Paillier secret key generation**: Can take 8+ seconds per member
  - **Safe primes generation**: Can take 1-2 seconds per member
- With 100 members, pre-params generation can take 2-3 minutes total
- Default timeout: `2 minutes` (`DefaultPreParamsGenerationTimeout`)
- Default concurrency: `1` (can be increased to `4`)

**Error Messages**:
```
failed to generate TSS pre-params: [timeout or error while generating the Paillier secret key]
failed to generate TSS pre-params: [timeout or error while generating the safe primes]
```

**Configuration** (in `pkg/tbtc/tbtc.go`):
```go
DefaultPreParamsGenerationTimeout     = 2 * time.Minute
DefaultPreParamsGenerationConcurrency = 1  // Can be increased to 4
```

**Fix**:
- Increase `PreParamsGenerationTimeout` in node configuration
- Increase `PreParamsGenerationConcurrency` to 4 (allows parallel generation)
- Ensure nodes have sufficient CPU resources
- Pre-generate pre-params pool before DKG starts

## 4. **Insufficient Quorum During Announcement Phase**

**Cause**: Not enough group members announce readiness within the announcement window.

**Details**:
- Each DKG attempt has an announcement phase (10 blocks active)
- Requires `GroupQuorum` members to announce readiness
- If quorum isn't reached, the attempt is skipped and retried

**Error Message**:
```
completed announcement phase for attempt [N] with non-quorum of [X] members ready to perform DKG
```

**Fix**:
- Ensure all nodes are running and connected
- Check network connectivity between nodes
- Verify nodes are properly registered in the sortition pool
- Increase announcement window if needed

## 5. **Network/Communication Failures**

**Cause**: Nodes cannot communicate during the DKG protocol execution.

**Details**:
- DKG requires P2P communication between all group members
- Network issues, firewall rules, or libp2p connection problems can cause failures
- Messages must be exchanged in multiple protocol rounds

**Error Messages**:
```
could not set up a broadcast channel: [error]
failed to get broadcast channel: [error]
```

**Fix**:
- Verify libp2p connectivity (`number of connected peers` in logs)
- Check firewall rules allow P2P communication
- Ensure nodes can discover each other via DHT
- Verify network configuration in node configs

## 6. **Block Time Too Fast**

**Cause**: Blocks are being mined faster than DKG can complete.

**Details**:
- DKG timeout is calculated in blocks, not time
- If blocks are mined very quickly (e.g., 1 second), DKG may timeout before completion
- With 100 members, DKG needs significant time for computation and communication

**Fix**:
- Adjust block time in Geth configuration (e.g., 12-15 seconds)
- Increase `SubmissionTimeoutBlocks` to account for faster blocks
- Monitor block time vs. DKG duration

## 7. **Insufficient Resources**

**Cause**: Nodes lack CPU, memory, or network bandwidth for DKG execution.

**Details**:
- DKG is computationally intensive (cryptographic operations)
- Requires significant memory for 100-member groups
- Network bandwidth needed for P2P message exchange

**Fix**:
- Ensure adequate CPU resources (4+ cores recommended)
- Monitor memory usage during DKG
- Check network bandwidth and latency
- Consider reducing group size for testing

## 8. **Member Exclusion Issues**

**Cause**: Too many members are excluded, leaving insufficient quorum.

**Details**:
- Members can be excluded if they misbehave or are inactive
- Need at least `GroupQuorum` active members to proceed
- If exclusion leaves fewer than quorum, DKG cannot complete

**Fix**:
- Ensure sufficient members are active and behaving correctly
- Check for misbehaving members in logs
- Verify group size is large enough to tolerate exclusions

## Common Solutions Summary

1. **Rebuild and restart nodes** with latest code (`dkgAttemptsLimit = 3`)
2. **Increase timeouts**:
   - `PreParamsGenerationTimeout` → 5 minutes
   - `PreParamsGenerationConcurrency` → 4
   - `SubmissionTimeoutBlocks` → 4000+ blocks
3. **Ensure proper block time** (12-15 seconds recommended)
4. **Verify network connectivity** between all nodes
5. **Check resource availability** (CPU, memory, network)
6. **Pre-generate pre-params** before DKG starts
7. **Monitor logs** for specific error patterns

## Monitoring DKG Status

Use the following scripts to monitor DKG:
- `scripts/check-dkg-status.sh` - Check overall DKG state
- `scripts/check-dkg-timeout-details.sh` - Check timeout information
- `scripts/check-node-dkg-joined.sh` - Verify nodes joined DKG

## Related Files

- `pkg/tbtc/dkg.go` - Main DKG execution logic
- `pkg/tbtc/dkg_loop.go` - DKG retry loop and attempt management
- `pkg/tbtc/node.go` - Timeout handling (`withCancelOnBlock`)
- `pkg/tbtc/tbtc.go` - DKG configuration defaults
