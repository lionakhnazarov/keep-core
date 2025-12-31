# Quick Start: Local Development Setup Summary

## 🚀 Complete Setup in 3 Steps

### Step 1: Start Geth
```bash
./scripts/start-geth-fast.sh
```

### Step 2: Deploy Everything
```bash
./scripts/complete-reset.sh
```
This deploys all contracts, initializes operators, and sets up the environment.

### Step 3: Create Wallet
```bash
./scripts/request-new-wallet.sh
```
Wait for DKG to complete (~5-10 minutes), then check:
```bash
./scripts/check-wallet-status.sh
```

---

## 📋 Detailed Steps

### Prerequisites
- Geth running and producing blocks
- All dependencies installed (Go, Node.js, Yarn, cast, jq)

### Setup Flow

```
1. Start Geth
   └─> ./scripts/start-geth-fast.sh
   
2. Deploy Contracts
   └─> ./scripts/complete-reset.sh
       ├─> Deploys Threshold Network contracts (T token, TokenStaking)
       ├─> Deploys ExtendedTokenStaking (development)
       ├─> Deploys Random Beacon contracts (ReimbursementPool, SortitionPool, DKG Validator, RandomBeacon, Chaosnet, Governance)
       ├─> Deploys ECDSA contracts (SortitionPool, DKG Validator, WalletRegistry, Governance)
       ├─> Deploys TBTC stubs (BridgeStub, MaintainerProxyStub, WalletProposalValidatorStub)
       ├─> Funds operators
       ├─> Initializes operators
       ├─> Joins operators to sortition pools
       ├─> Sets DKG parameters
       └─> Sets WalletOwner
       
   See docs/LOCAL_DEVELOPMENT_SETUP.md for complete contract list
   
3. Create Wallet
   └─> ./scripts/request-new-wallet.sh
       ├─> Triggers DKG process
       ├─> DKG runs off-chain (TSS rounds)
       ├─> DKG result submitted
       ├─> DKG result approved
       └─> Wallet created
   
4. Verify Wallet
   └─> ./scripts/check-wallet-status.sh
```

---

## 🔧 Common Operations

### Check Wallet Status
```bash
./scripts/check-wallet-status.sh
```

### Prepare Deposit Data
```bash
./scripts/emulate-deposit.sh [depositor] [amount_satoshis]
# Example: ./scripts/emulate-deposit.sh 0x1234...abcd 100000000
```

### Deploy Complete Bridge (for deposit testing)
```bash
./scripts/deploy-bridge-complete.sh
```

### Monitor Events
```bash
./scripts/monitor-tbtc-events.sh
```

### Restart Nodes
```bash
./scripts/restart-all-nodes.sh
```

---

## 🐛 Troubleshooting

| Issue | Solution |
|-------|----------|
| Geth not producing blocks | `./scripts/start-geth-fast.sh` (removes chaindata) |
| Operators not joining pools | Check `eligibleStake`, re-run `initialize-all-operators.sh` |
| DKG stuck | Wait for timeout or run `reset-dkg-if-timed-out.sh` |
| WalletOwner not set | Run `init-wallet-owner.ts` script |
| DKG approval fails | Ensure BridgeStub has callback functions, redeploy |

---

## 📁 Key Files & Directories

```
keep-core/
├── scripts/
│   ├── complete-reset.sh          # Full setup script
│   ├── request-new-wallet.sh       # Create wallet
│   ├── check-wallet-status.sh      # List wallets
│   ├── emulate-deposit.sh          # Prepare deposit data
│   └── deploy-bridge-complete.sh  # Deploy full Bridge
├── solidity/
│   ├── ecdsa/deployments/          # ECDSA contract addresses
│   ├── random-beacon/deployments/  # RandomBeacon addresses
│   └── tbtc-stub/deployments/     # BridgeStub addresses
├── deposit-data/                   # Generated deposit data
└── logs/                           # Node logs
```

---

## 🔍 Verification Commands

```bash
# Check Geth is running
cast block-number --rpc-url http://localhost:8545

# Check contract addresses
jq -r '.address' solidity/ecdsa/deployments/development/WalletRegistry.json
jq -r '.address' solidity/tbtc-stub/deployments/development/BridgeStub.json

# Check DKG state
WR=$(jq -r '.address' solidity/ecdsa/deployments/development/WalletRegistry.json)
cast call $WR "getWalletCreationState()" --rpc-url http://localhost:8545

# Check walletOwner
cast call $WR "walletOwner()" --rpc-url http://localhost:8545
```

---

## 📚 Full Documentation

For detailed information, see:
- `docs/FRESH_SETUP_CHECKLIST.md` - Step-by-step checklist (printable)
- `docs/LOCAL_DEVELOPMENT_SETUP.md` - Complete setup guide with detailed explanations
- `docs/development/README.adoc` - Development documentation
- Individual script files - Inline comments and usage

---

## ⚡ One-Liner Setup

```bash
./scripts/start-geth-fast.sh && sleep 5 && ./scripts/complete-reset.sh && sleep 30 && ./scripts/request-new-wallet.sh
```

Then monitor:
```bash
tail -f logs/node1.log | grep -i "wallet\|dkg"
```
