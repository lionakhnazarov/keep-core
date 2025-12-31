# How to Check if Operator is in Sortition Pool

## Overview

There are two sortition pools in the Keep Network:
1. **RandomBeacon Sortition Pool** - For Random Beacon operations
2. **WalletRegistry Sortition Pool** - For ECDSA wallet operations

Operators must be in both pools to participate in DKG and other operations.

## Quick Check Script

Use the provided script to check all operators:

```bash
# Check all operators from node configs
./scripts/check-operator-in-pool.sh

# Check a specific operator
./scripts/check-operator-in-pool.sh <OPERATOR_ADDRESS>
```

## Manual CLI Commands

### Check RandomBeacon Pool

```bash
# Check if operator is in RandomBeacon sortition pool
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum beacon random-beacon is-operator-in-pool \
  <OPERATOR_ADDRESS> \
  --config configs/config.toml \
  --developer
```

**Output:**
- `true` - Operator is in the pool
- `false` - Operator is NOT in the pool

### Check WalletRegistry Pool

```bash
# Check if operator is in WalletRegistry sortition pool
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry is-operator-in-pool \
  <OPERATOR_ADDRESS> \
  --config configs/config.toml \
  --developer
```

**Output:**
- `true` - Operator is in the pool
- `false` - Operator is NOT in the pool

## Check All Operators from Node Configs

### Using the Script

```bash
./scripts/check-operator-in-pool.sh
```

This will:
1. Find all `node*.toml` config files
2. Extract operator addresses from each config
3. Check both RandomBeacon and WalletRegistry pools
4. Display a table with results

**Example output:**
```
Node       Operator Address                              RandomBeacon        WalletRegistry
--------------------------------------------------------------------------------------------------------
node1      0x99d0a790100489503a68BA3a3a41C45a3a6C7039   ✓                  ✓
node2      0xFcFe77a8d836E6D8AFeDbA29F432a98Fbd44290b   ✓                  ✓
node3      0xB906273E9a3b854198f8CAB327c53460f4937c31   ✗                  ✗
...
```

### Manual Check for Each Node

```bash
# Get operator address from node config
OPERATOR=$(grep -A1 "^Address:" configs/node1.toml | tail -1 | tr -d ' ')

# Check RandomBeacon
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum beacon random-beacon is-operator-in-pool \
  "$OPERATOR" \
  --config configs/node1.toml \
  --developer

# Check WalletRegistry
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry is-operator-in-pool \
  "$OPERATOR" \
  --config configs/node1.toml \
  --developer
```

## Other Useful Commands

### Check if Operator is Up-to-Date

```bash
# RandomBeacon
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum beacon random-beacon is-operator-up-to-date \
  <OPERATOR_ADDRESS> \
  --config configs/config.toml \
  --developer

# WalletRegistry
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry is-operator-up-to-date \
  <OPERATOR_ADDRESS> \
  --config configs/config.toml \
  --developer
```

This checks if the operator's authorized stake matches their weight in the pool.

### Get Operator ID in Pool

```bash
# RandomBeacon
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum beacon random-beacon sortition-pool get-operator-id \
  <OPERATOR_ADDRESS> \
  --config configs/config.toml \
  --developer

# WalletRegistry
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry sortition-pool get-operator-id \
  <OPERATOR_ADDRESS> \
  --config configs/config.toml \
  --developer
```

### Get Total Operators in Pool

```bash
# RandomBeacon
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum beacon random-beacon sortition-pool operators-in-pool \
  --config configs/config.toml \
  --developer

# WalletRegistry
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry sortition-pool operators-in-pool \
  --config configs/config.toml \
  --developer
```

## Using Cast (Direct Contract Call)

You can also check directly using `cast`:

```bash
# Get contract addresses
RB_POOL=$(jq -r '.address' solidity/random-beacon/deployments/development/BeaconSortitionPool.json)
WR_POOL=$(jq -r '.address' solidity/ecdsa/deployments/development/EcdsaSortitionPool.json)

# Check RandomBeacon pool
cast call "$RB_POOL" "isOperatorInPool(address)(bool)" <OPERATOR_ADDRESS> \
  --rpc-url http://localhost:8545

# Check WalletRegistry pool
cast call "$WR_POOL" "isOperatorInPool(address)(bool)" <OPERATOR_ADDRESS> \
  --rpc-url http://localhost:8545
```

## Troubleshooting

### Operator Not in Pool

If an operator is not in the pool:

1. **Check if operator is registered**:
   ```bash
   KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum beacon random-beacon operator-to-staking-provider \
     <OPERATOR_ADDRESS> \
     --config configs/config.toml \
     --developer
   ```

2. **Check if operator has authorization**:
   ```bash
   # Check authorized stake
   KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum threshold token-staking authorized-stake \
     <STAKING_PROVIDER_ADDRESS> \
     --config configs/config.toml \
     --developer
   ```

3. **Join the pool**:
   ```bash
   # RandomBeacon
   KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum beacon random-beacon join-sortition-pool \
     --submit \
     --config configs/node1.toml \
     --developer
   
   # WalletRegistry
   KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry join-sortition-pool \
     --submit \
     --config configs/node1.toml \
     --developer
   ```

### Join All Operators

Use the script to join all operators:

```bash
./scripts/join-all-operators-to-pools.sh
```

## Requirements for Being in Pool

An operator must have:

1. ✅ **Registered**: Operator registered with staking provider
2. ✅ **Authorized**: Sufficient authorization (above minimum threshold)
3. ✅ **Joined**: Called `joinSortitionPool()` successfully
4. ✅ **Up-to-date**: Authorized stake matches pool weight

## Summary

**Quick check:**
```bash
./scripts/check-operator-in-pool.sh
```

**Check specific operator:**
```bash
./scripts/check-operator-in-pool.sh <OPERATOR_ADDRESS>
```

**Manual check:**
```bash
# RandomBeacon
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum beacon random-beacon is-operator-in-pool \
  <OPERATOR_ADDRESS> --config configs/config.toml --developer

# WalletRegistry
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry is-operator-in-pool \
  <OPERATOR_ADDRESS> --config configs/config.toml --developer
```
