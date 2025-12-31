#!/bin/bash
# Script to transfer EcdsaSortitionPool ownership to WalletRegistry

set -e

ECDSA_SP="0x6085ff3bcFA73aB7B1e244286c712E5f82FdB48A"
WALLET_REGISTRY="0x50E550fDEAC9DEFEf3Bb3a03cb0Fa1d4C37Af5ab"
CURRENT_OWNER="0xf40c5B4749991Bf5C5E5a78dAD469A980402a0a3"

echo "=========================================="
echo "Fixing EcdsaSortitionPool Ownership"
echo "=========================================="
echo ""
echo "EcdsaSortitionPool: $ECDSA_SP"
echo "Current owner: $CURRENT_OWNER"
echo "Target owner: $WALLET_REGISTRY"
echo ""
echo "This will unlock the current owner and transfer ownership"
echo "Press Enter to continue..."
read

geth attach http://localhost:8545 <<EOF
// Function selector for transferOwnership(address): 0xf2fde38b
var functionSelector = "0xf2fde38b";
var targetAddress = "$WALLET_REGISTRY".slice(2).padStart(64, "0");
var data = functionSelector + targetAddress;

console.log("Unlocking current owner...");
try {
  personal.unlockAccount("$CURRENT_OWNER", "password", 0);
  console.log("✓ Account unlocked");
} catch(e) {
  try {
    personal.unlockAccount("$CURRENT_OWNER", "", 0);
    console.log("✓ Account unlocked with empty password");
  } catch(e2) {
    console.log("⚠️  Could not unlock account");
    console.log("   Please unlock manually: personal.unlockAccount('$CURRENT_OWNER', 'password', 0)");
    exit;
  }
}

console.log("Transferring ownership...");
console.log("Data: " + data);
var tx = eth.sendTransaction({
  from: "$CURRENT_OWNER",
  to: "$ECDSA_SP",
  data: data,
  gas: 100000
});
console.log("Transaction hash: " + tx);

// Wait for confirmation
var receipt = null;
var attempts = 0;
while (receipt === null && attempts < 30) {
  receipt = eth.getTransactionReceipt(tx);
  if (receipt === null) {
    admin.sleep(1);
    attempts++;
  }
}

if (receipt !== null && receipt.status === "0x1") {
  console.log("✓ Ownership transferred successfully!");
  console.log("   Block: " + receipt.blockNumber);
  
  // Verify new owner
  var newOwner = eth.call({
    to: "$ECDSA_SP",
    data: "0x8da5cb5b" // owner() function selector
  });
  console.log("New owner: 0x" + newOwner.slice(-40));
} else {
  console.log("⚠️  Transaction failed or not confirmed");
  if (receipt) {
    console.log("   Status: " + receipt.status);
  }
}
EOF

echo ""
echo "=========================================="
echo "Done!"
echo "=========================================="
