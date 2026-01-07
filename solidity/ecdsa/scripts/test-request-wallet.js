const hre = require("hardhat");

async function main() {
  const { deployments } = hre;
  const WalletRegistry = await deployments.get("WalletRegistry");
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address);
  
  const walletOwner = await wr.walletOwner();
  console.log("Wallet Owner:", walletOwner);
  console.log("Expected:  0x7966c178f466b060aaeb2b91e9149a5fb2ec9c53");
  console.log("Match:", walletOwner.toLowerCase() === "0x7966c178f466b060aaeb2b91e9149a5fb2ec9c53".toLowerCase());
  
  // Get account that matches wallet owner
  const accounts = await ethers.getSigners();
  let matchingAccount = null;
  for (const account of accounts) {
    if (account.address.toLowerCase() === walletOwner.toLowerCase()) {
      matchingAccount = account;
      break;
    }
  }
  
  if (!matchingAccount) {
    console.log("\n⚠️  No signer matches wallet owner");
    console.log("Available accounts:");
    for (const account of accounts) {
      console.log("  -", account.address);
    }
    return;
  }
  
  console.log("\n✓ Found matching account:", matchingAccount.address);
  
  // Check DKG state
  const dkgState = await wr.getWalletCreationState();
  const states = ["IDLE", "AWAITING_SEED", "AWAITING_RESULT", "CHALLENGE"];
  console.log("\nDKG State:", states[dkgState] || `UNKNOWN(${dkgState})`);
  
  if (dkgState !== 0) {
    console.log("⚠️  DKG is not in IDLE state. Cannot request new wallet.");
    return;
  }
  
  console.log("\nCalling requestNewWallet()...");
  try {
    const tx = await wr.connect(matchingAccount).requestNewWallet({ gasLimit: 500000 });
    console.log("Transaction submitted:", tx.hash);
    const receipt = await tx.wait();
    if (receipt.status === 1) {
      console.log("✓ Success! Confirmed in block:", receipt.blockNumber);
    } else {
      console.log("❌ Transaction reverted");
      // Try to get revert reason
      try {
        await wr.connect(matchingAccount).callStatic.requestNewWallet({ gasLimit: 500000 });
      } catch (staticError) {
        console.log("Revert reason:", staticError.reason || staticError.message);
      }
    }
  } catch (error) {
    console.log("❌ Error:", error.message);
    if (error.reason) {
      console.log("Reason:", error.reason);
    }
    // Try static call to get revert reason
    try {
      await wr.connect(matchingAccount).callStatic.requestNewWallet({ gasLimit: 500000 });
    } catch (staticError) {
      console.log("Static call revert:", staticError.reason || staticError.message);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

