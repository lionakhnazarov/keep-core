# Mock Bitcoin Chain Setup for Deposit Sweep Testing

## The Problem

When you reveal a deposit, the `DepositRevealed` event is emitted, but the deposit cannot be swept because:

1. **Bitcoin Transaction Hash Mismatch**: The funding transaction hash in your deposit reveal was randomly generated (from `emulate-deposit.sh`) and doesn't correspond to a real Bitcoin transaction.

2. **Deterministic Hashes**: Bitcoin transaction hashes are deterministic SHA256 hashes calculated from the transaction content. You cannot create a transaction with a specific hash - the hash is determined by the transaction data.

3. **Confirmation Requirement**: The deposit sweep process requires the funding transaction to have 6+ confirmations on the Bitcoin chain. Since the transaction doesn't exist, this check fails.

## Solutions

### Option 1: Mock Electrum Server (Recommended for Local Testing)

Create a mock Electrum server that:
- Intercepts queries for the funding transaction hash
- Returns transaction data reconstructed from the deposit reveal
- Reports 6+ confirmations

**Pros:**
- Works with existing deposit reveals
- No need to modify contracts
- Easy to set up

**Cons:**
- Requires running a mock server
- Nodes need to be configured to use it

### Option 2: Create Transaction First, Then Reveal

1. Create a Bitcoin transaction on regtest FIRST
2. Get its hash
3. Use that hash when revealing the deposit

**Pros:**
- Uses real Bitcoin transactions
- More realistic testing

**Cons:**
- Requires re-doing the deposit reveal
- More complex setup

### Option 3: Modify Bridge Contract (Testing Only)

Temporarily disable Bitcoin transaction verification in the Bridge contract.

**Pros:**
- Simplest for quick testing

**Cons:**
- Requires contract modification
- Not realistic
- **NEVER use in production**

## Recommended Approach: Mock Electrum Server

Since your deposit is already revealed, Option 1 is the best choice. Here's how to set it up:

### Step 1: Extract Transaction Data

The deposit reveal contains `BitcoinTxInfo` which has:
- `version`: Transaction version
- `inputVector`: Serialized inputs
- `outputVector`: Serialized outputs  
- `locktime`: Transaction locktime

### Step 2: Create Mock Electrum Server

A mock Electrum server needs to:
1. Listen on a port (e.g., 50001)
2. Implement Electrum protocol methods:
   - `blockchain.transaction.get` - Return transaction data
   - `blockchain.transaction.get_merkle` - Return merkle proof
   - `blockchain.block.header` - Return block headers
   - `blockchain.scripthash.get_history` - Return transaction history

3. When queried for the funding TX hash:
   - Reconstruct the raw transaction from `BitcoinTxInfo`
   - Return it in Electrum format
   - Report it as confirmed with 6+ confirmations

### Step 3: Configure Nodes

Update `config.toml`:
```toml
[bitcoin.electrum]
URL = "tcp://localhost:50001"
```

### Step 4: Restart Nodes

Restart all nodes so they connect to the mock server.

## Quick Start Script

Run:
```bash
./scripts/setup-mock-bitcoin-for-deposits.sh
```

This will:
1. Check for revealed deposits
2. Set up Bitcoin regtest node
3. Explain the transaction hash issue
4. Provide next steps

## Current Status

Your deposit reveal exists with:
- Funding TX Hash: `0xaf2acdaaedf65c24036c7c0a239093d53f96810ab393360515b027190bf0a18`
- This hash doesn't exist on any Bitcoin chain
- Nodes cannot verify it has 6+ confirmations
- Deposit sweep is blocked

## Next Steps

1. **Create Mock Electrum Server**: Implement a server that returns transaction data for the funding hash
2. **Update Config**: Point nodes to the mock server
3. **Restart Nodes**: Nodes will then see the transaction with confirmations
4. **Monitor Sweep**: Watch for `DepositSwept` events

## Files Created

- `scripts/setup-mock-bitcoin-for-deposits.sh` - Setup script
- `scripts/add-funding-tx-to-bitcoin.sh` - Transaction injection script
- `scripts/create-mock-bitcoin-tx.go` - Go tool for transaction creation

## Notes

- The mock Electrum server approach is the most practical for local testing
- In production, deposits use real Bitcoin transactions with real hashes
- The deposit reveal step works correctly - the issue is only with Bitcoin chain verification

