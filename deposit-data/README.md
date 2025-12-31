# Deposit Data for Testing

This directory contains deposit data structures prepared for tBTC testing.

## Files

- **deposit-data.json** - Complete deposit information including all parameters
- **funding-tx-info.json** - BitcoinTxInfo structure for `revealDeposit()` call
- **deposit-reveal-info.json** - DepositDepositRevealInfo structure for `revealDeposit()` call

## Usage

### Regenerate Deposit Data

```bash
./scripts/emulate-deposit.sh [depositor_address] [amount_satoshis]
```

Examples:
```bash
# Use default values (random depositor, 1 BTC)
./scripts/emulate-deposit.sh

# Specify depositor address
./scripts/emulate-deposit.sh 0x1234...abcd

# Specify depositor and amount (0.5 BTC = 50000000 satoshis)
./scripts/emulate-deposit.sh 0x1234...abcd 50000000
```

### Using the Data

The generated JSON files can be used with:

1. **keep-client** (if Bridge supports revealDeposit):
```bash
keep-client bridge reveal-deposit \
  --funding-tx-info "$(cat funding-tx-info.json | jq -c .)" \
  --deposit-reveal-info "$(cat deposit-reveal-info.json | jq -c .)"
```

2. **cast** (if Bridge contract has revealDeposit function):
```bash
cast send <BRIDGE_ADDRESS> \
  "revealDeposit((bytes4,bytes,bytes,bytes4),(uint32,bytes8,bytes20,bytes20,bytes4,address))" \
  "$(cat funding-tx-info.json | jq -c .)" \
  "$(cat deposit-reveal-info.json | jq -c .)" \
  --rpc-url http://localhost:8545
```

## Data Structure Details

### BitcoinTxInfo
- `version`: Bitcoin transaction version (4 bytes)
- `inputVector`: Serialized transaction inputs
- `outputVector`: Serialized transaction outputs
- `locktime`: Transaction locktime (4 bytes)

### DepositDepositRevealInfo
- `fundingOutputIndex`: Index of the output in funding transaction
- `blindingFactor`: 8-byte random value to distinguish deposits
- `walletPubKeyHash`: 20-byte hash of wallet public key (RIPEMD160(SHA256(compressed_pubkey)))
- `refundPubKeyHash`: 20-byte hash of refund public key
- `refundLocktime`: 4-byte refund locktime
- `vault`: Optional vault address (zero if not used)

## Notes

- The wallet public key hash is calculated from the actual wallet created via DKG
- Funding transaction data is mocked for testing purposes
- In production, these would come from actual Bitcoin transactions
- BridgeStub doesn't implement `revealDeposit()` - deploy full Bridge contract for testing
