#!/bin/bash
# Script to request a new wallet using geth console
# This calls Bridge.requestNewWallet() which forwards to WalletRegistry

set -e

# Get Bridge address from deployment
cd "$(dirname "$0")/.."
BRIDGE=$(cat solidity/tbtc-stub/deployments/development/Bridge.json 2>/dev/null | jq -r '.address')

if [ -z "$BRIDGE" ] || [ "$BRIDGE" = "null" ]; then
  echo "Error: Could not find Bridge deployment"
  echo "Please deploy Bridge first:"
  echo "  cd solidity/tbtc-stub && npx hardhat deploy --network development --tags TBTCStubs"
  exit 1
fi

echo "=========================================="
echo "Requesting New Wallet (Triggering DKG)"
echo "=========================================="
echo ""
echo "Bridge address: $BRIDGE"
echo ""
echo "This script will use geth console to call Bridge.requestNewWallet()"
echo "Bridge will forward the call to WalletRegistry"
echo ""
echo "Instructions:"
echo "1. The geth console will open"
echo "2. Try unlocking with password 'password' (common default)"
echo "3. If that fails, try with an empty password"
echo "4. Then execute the transaction"
echo ""
echo "Press Enter to continue..."
read

geth attach http://localhost:8545 <<EOF
// Try to unlock account with common passwords
var account = eth.accounts[0];
console.log("Using account: " + account);
console.log("Account balance: " + web3.fromWei(eth.getBalance(account), "ether") + " ETH");

// Try common passwords (most setups use "password")
var unlocked = false;
try {
  personal.unlockAccount(account, "password", 0);
  console.log("✓ Account unlocked with password 'password'");
  unlocked = true;
} catch(e) {
  try {
    personal.unlockAccount(account, "", 0);
    console.log("✓ Account unlocked with empty password");
    unlocked = true;
  } catch(e2) {
    console.log("⚠️  Could not unlock account automatically");
    console.log("   Error: " + e2);
    console.log("");
    console.log("Please unlock manually in geth console:");
    console.log("   geth attach http://localhost:8545");
    console.log("   > personal.unlockAccount(eth.accounts[0], 'password', 0)");
    console.log("   > eth.sendTransaction({from: eth.accounts[0], to: '$BRIDGE', data: '0x72cc8c6d', gas: 500000})");
    exit;
  }
}

if (!unlocked) {
  exit;
}

// Call Bridge.requestNewWallet()
console.log("Calling Bridge.requestNewWallet()...");
var tx = eth.sendTransaction({
  from: account,
  to: '$BRIDGE',
  data: '0x72cc8c6d',
  gas: 500000
});
console.log("Transaction submitted: " + tx);
console.log("Waiting for confirmation...");

// Wait for transaction
var receipt = null;
var attempts = 0;
while (receipt === null && attempts < 30) {
  receipt = eth.getTransactionReceipt(tx);
  if (receipt === null) {
    admin.sleep(1);
    attempts++;
  }
}

if (receipt !== null) {
  if (receipt.status === "0x1") {
    console.log("✓ DKG triggered successfully!");
    console.log("   Block: " + receipt.blockNumber);
    console.log("   Gas used: " + receipt.gasUsed);
  } else {
    console.log("⚠️  Transaction reverted");
    console.log("   Receipt: " + JSON.stringify(receipt));
  }
} else {
  console.log("⚠️  Transaction not confirmed after 30 seconds");
  console.log("   Transaction hash: " + tx);
  console.log("   Check status with: eth.getTransactionReceipt('" + tx + "')");
}
EOF

echo ""
echo "=========================================="
echo "Done!"
echo "=========================================="
