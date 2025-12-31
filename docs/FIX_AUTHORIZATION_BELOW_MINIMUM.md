# Fix "Authorization below the minimum" Error

## Problem

Error: `execution reverted: Authorization below the minimum`

This error occurs when trying to join sortition pools, but operators don't have sufficient authorized stake.

## Root Cause

Operators need to be **initialized** (staked and authorized) before they can join sortition pools. The minimum authorization required is:
- **WalletRegistry**: 40,000 T tokens
- **RandomBeacon**: 40,000 T tokens

## Solution

### Step 1: Initialize All Operators

Run the initialization script to stake and authorize all operators:

```bash
./scripts/initialize-all-operators.sh
```

This script will:
1. Find all operator addresses from node configs
2. Stake T tokens for each operator
3. Authorize each operator for both RandomBeacon and WalletRegistry
4. Use minimum authorization by default (or specify custom amount)

**With custom authorization amount:**
```bash
AUTHORIZATION_AMOUNT=50000 ./scripts/initialize-all-operators.sh
```

### Step 2: Verify Authorization

Check that operators now have sufficient authorization:

```bash
# Check if operators are in pools (they should be able to join now)
./scripts/check-operator-in-pool.sh

# Or check specific operator's eligible stake
WR=$(jq -r '.address' solidity/ecdsa/deployments/development/WalletRegistry.json)
OPERATOR="0x<OPERATOR_ADDRESS>"
STAKING_PROVIDER=$(cast call "$WR" "operatorToStakingProvider(address)(address)" "$OPERATOR" --rpc-url http://localhost:8545)
cast call "$WR" "eligibleStake(address)(uint256)" "$STAKING_PROVIDER" --rpc-url http://localhost:8545
```

### Step 3: Join Sortition Pools

After initialization, join operators to pools:

```bash
./scripts/join-all-operators-to-pools.sh
```

## Manual Initialization

If the script doesn't work, initialize manually:

```bash
# For each operator
OPERATOR="0x<OPERATOR_ADDRESS>"

# Initialize RandomBeacon
cd solidity/random-beacon
npx hardhat initialize \
  --network development \
  --owner "$OPERATOR" \
  --provider "$OPERATOR" \
  --operator "$OPERATOR" \
  --beneficiary "$OPERATOR" \
  --authorizer "$OPERATOR" \
  --amount 1000000 \
  --authorization 50000

# Initialize WalletRegistry
cd ../ecdsa
npx hardhat initialize \
  --network development \
  --owner "$OPERATOR" \
  --provider "$OPERATOR" \
  --operator "$OPERATOR" \
  --beneficiary "$OPERATOR" \
  --authorizer "$OPERATOR" \
  --amount 1000000 \
  --authorization 50000
```

## Check Minimum Authorization

```bash
# WalletRegistry
WR=$(jq -r '.address' solidity/ecdsa/deployments/development/WalletRegistry.json)
cast call "$WR" "minimumAuthorization()(uint96)" --rpc-url http://localhost:8545

# RandomBeacon
RB=$(jq -r '.address' solidity/random-beacon/deployments/development/RandomBeacon.json)
cast call "$RB" "minimumAuthorization()(uint96)" --rpc-url http://localhost:8545
```

## Check Current Authorization

```bash
OPERATOR="0x<OPERATOR_ADDRESS>"
WR=$(jq -r '.address' solidity/ecdsa/deployments/development/WalletRegistry.json)
STAKING_PROVIDER=$(cast call "$WR" "operatorToStakingProvider(address)(address)" "$OPERATOR" --rpc-url http://localhost:8545)

# Check eligible stake (what's available for pool)
cast call "$WR" "eligibleStake(address)(uint256)" "$STAKING_PROVIDER" --rpc-url http://localhost:8545

# Check authorized stake (from TokenStaking)
STAKING=$(jq -r '.address' solidity/random-beacon/deployments/development/TokenStaking.json)
cast call "$STAKING" "authorizedStake(address,address)(uint256)" "$STAKING_PROVIDER" "$WR" --rpc-url http://localhost:8545
```

## Expected Values

- **Minimum authorization**: 40,000 T tokens (40000000000000000000000 wei)
- **Recommended authorization**: 50,000+ T tokens (to be safe)
- **Stake amount**: 1,000,000 T tokens (for staking)

## Summary

**Quick fix:**
```bash
# 1. Initialize all operators (stake + authorize)
./scripts/initialize-all-operators.sh

# 2. Join sortition pools
./scripts/join-all-operators-to-pools.sh

# 3. Verify
./scripts/check-operator-in-pool.sh
```

The initialization script handles staking and authorization automatically. After running it, operators should have sufficient authorization to join the pools.
