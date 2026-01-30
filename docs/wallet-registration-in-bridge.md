# Wallet Registration in Bridge

## Problem

When wallets are created via DKG, they are registered in `WalletRegistry` but **not automatically registered in the Bridge contract**. This causes redemption requests to fail with:

```
Error: Wallet must be in Live state
```

## Root Cause

The Bridge stub's `__ecdsaWalletCreatedCallback()` function is currently empty (a stub implementation). When `WalletRegistry` calls this callback after DKG completes, it doesn't register the wallet in Bridge.

## Solution

### Option 1: Redeploy Bridge Stub (Recommended)

1. The Bridge stub contract has a `registerWallet()` function that can manually register wallets
2. However, the currently deployed Bridge stub doesn't include this function
3. Redeploy the Bridge stub to include `registerWallet()`
4. Then run the registration script: `./scripts/register-wallets-in-bridge.sh`

### Option 2: Manual Registration (Temporary Workaround)

For existing wallets, you can manually register them using `cast`:

```bash
# Get wallet public key from WalletRegistry
WALLET_ID="0x..." # From WalletCreated event
PUBLIC_KEY=$(cast call $WALLET_REGISTRY "getWalletPublicKey(bytes32)(bytes)" $WALLET_ID --rpc-url http://localhost:8545)

# Calculate walletPubKeyHash (requires off-chain calculation)
# This is SHA256+RIPEMD160 of compressed public key
# Use the register-wallets-in-bridge.ts script to calculate this

# Register wallet in Bridge (once registerWallet function is available)
cast send $BRIDGE "registerWallet(bytes20,bytes32)" $WALLET_PUBKEY_HASH $WALLET_ID \
  --rpc-url http://localhost:8545 \
  --unlocked --from $DEPLOYER
```

### Option 3: Update Callback (Future)

Update `__ecdsaWalletCreatedCallback()` in Bridge stub to automatically register wallets. This requires implementing RIPEMD160 hash calculation on-chain (or using a library).

## Current Status

- ✅ Wallets are created in WalletRegistry via DKG
- ❌ Wallets are NOT automatically registered in Bridge
- ❌ Redemption requests fail because wallets aren't in "Live" state
- ⚠️  Bridge stub needs to be redeployed with `registerWallet()` function

## Next Steps

1. Redeploy Bridge stub contract with `registerWallet()` function
2. Run registration script for existing wallets
3. Future wallets will need manual registration until callback is implemented
