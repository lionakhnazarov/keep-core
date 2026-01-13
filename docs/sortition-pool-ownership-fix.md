# Fix: SortitionPool Ownership for unlock() to Work

## Problem

The `approveDkgResult()` transaction reverts at `sortitionPool.unlock()` because:
- SortitionPool owner: WalletRegistry contract
- `msg.sender` when `unlock()` is called: deployer account (transaction sender)
- `onlyOwner` check fails: `msg.sender != owner()` → revert

## Root Cause

`msg.sender` is always the original transaction sender, not the contract itself. Even though `unlock()` is called from within WalletRegistry code, `msg.sender` remains the deployer account.

## Solution

**Make the deployer account the owner of SortitionPool instead of WalletRegistry.**

### For New Deployments

The deployment script (`solidity/ecdsa/deploy/03_deploy_wallet_registry.ts`) has been modified to:
- **Skip** transferring ownership to WalletRegistry
- **Keep** deployer as the owner
- Log a warning if ownership is already set to WalletRegistry

### For Existing Deployments

Since WalletRegistry is a contract (not an EOA), we cannot directly call `transferOwnership` from it. Options:

#### Option 1: Add Function to WalletRegistry (Recommended)

Add a function to WalletRegistry that calls `sortitionPool.transferOwnership()`:

```solidity
function transferSortitionPoolOwnership(address newOwner) external onlyGovernance {
    sortitionPool.transferOwnership(newOwner);
}
```

Then use governance to execute this function.

#### Option 2: Use Governance

If WalletRegistry has governance functions, use them to execute the ownership transfer.

#### Option 3: Redeploy

Redeploy the contracts with the modified deployment script that keeps deployer as owner.

### Manual Transfer (Local Development Only)

For local development, you can use Hardhat's account impersonation:

```bash
cd solidity/ecdsa
npx hardhat run scripts/transfer-sortition-pool-owner-to-deployer.ts --network development
```

**Note:** This only works on local/test networks that support account impersonation.

## Verification

After transferring ownership, verify:

```bash
# Check SortitionPool owner
cast call <SORTITION_POOL_ADDRESS> "owner()" --rpc-url http://localhost:8545

# Should return deployer address, not WalletRegistry address
```

## Files Modified

1. `solidity/ecdsa/deploy/03_deploy_wallet_registry.ts` - Modified to skip ownership transfer
2. `solidity/ecdsa/scripts/transfer-sortition-pool-owner-to-deployer.ts` - Script for local dev
3. `docs/sortition-pool-ownership-fix.md` - This documentation

## Testing

After fixing ownership, test that `approveDkgResult()` works:

```bash
cd solidity/ecdsa
npx hardhat run scripts/approve-dkg-from-event.ts --network development
```

The transaction should succeed and `unlock()` should not revert.


