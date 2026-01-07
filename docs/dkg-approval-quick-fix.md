# DKG Approval Quick Fix Guide

## Quick Fix: Approve Using Event Data

When DKG is stuck in CHALLENGE state due to hash mismatch, use this workaround:

```bash
./scripts/approve-dkg-from-event.sh
```

This script extracts the exact DKG result from the submission event and approves it directly, bypassing the hash mismatch issue.

## What This Does

1. Finds the DKG result submission event
2. Extracts the exact result structure that was submitted
3. Uses that exact structure to approve (no reconstruction)
4. Bypasses the hash mismatch because it uses the same data

## Prerequisites

- DKG must be in CHALLENGE state (state 3)
- Challenge period must have ended
- Precedence period should have ended (or you must be the submitter)

## Alternative: Manual Approval

If the script doesn't work, you can run it manually:

```bash
cd solidity/ecdsa
npx hardhat run scripts/approve-dkg-from-event.ts --network development
```

## Diagnosis

To diagnose the issue:

```bash
./scripts/diagnose-dkg-approval.sh
```

This will show:
- Current DKG state
- Block numbers and timing
- Submission event details
- Recent approval attempts
- WalletOwner status

## Check Hash Mismatch

To see the hash mismatch details:

```bash
cd solidity/ecdsa
npx hardhat run scripts/check-dkg-result-hash.ts --network development
```

## Related Documentation

- [DKG Hash Mismatch Issue](./dkg-hash-mismatch-issue.md) - Detailed explanation
- [PROCEED_FROM_CHALLENGE.md](./PROCEED_FROM_CHALLENGE.md) - Original challenge guide

