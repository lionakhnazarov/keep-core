const hre = require("hardhat");

async function main() {
  const newWalletOwner = process.argv[2] || "0x7966c178f466b060aaeb2b91e9149a5fb2ec9c53";
  
  console.log("=== Update Wallet Owner ===");
  console.log(`New Wallet Owner: ${newWalletOwner}\n`);
  
  const { deployments } = hre;
  const Governance = await deployments.get("WalletRegistryGovernance");
  const gov = await ethers.getContractAt("WalletRegistryGovernance", Governance.address);
  
  const [deployer] = await ethers.getSigners();
  console.log(`Using deployer: ${deployer.address}\n`);
  
  // Check current wallet owner
  const WalletRegistry = await deployments.get("WalletRegistry");
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address);
  const currentOwner = await wr.walletOwner();
  console.log(`Current Wallet Owner: ${currentOwner}\n`);
  
  if (currentOwner.toLowerCase() === newWalletOwner.toLowerCase()) {
    console.log("✓ Wallet owner is already set to this address!");
    return;
  }
  
  // Check governance delay
  const governanceDelay = await gov.governanceDelay();
  console.log(`Governance Delay: ${governanceDelay.toString()} seconds\n`);
  
  // Begin update
  console.log("Step 1: Beginning wallet owner update...");
  try {
    const beginTx = await gov.connect(deployer).beginWalletOwnerUpdate(newWalletOwner);
    const beginReceipt = await beginTx.wait();
    console.log(`✓ Update initiated in block: ${beginReceipt.blockNumber}`);
    console.log(`  Transaction: ${beginTx.hash}\n`);
    
    if (governanceDelay.eq(0)) {
      console.log("Governance delay is 0, finalizing immediately...\n");
      
      // Finalize immediately if delay is 0
      console.log("Step 2: Finalizing wallet owner update...");
      const finalizeTx = await gov.connect(deployer).finalizeWalletOwnerUpdate();
      const finalizeReceipt = await finalizeTx.wait();
      console.log(`✓ Update finalized in block: ${finalizeReceipt.blockNumber}`);
      console.log(`  Transaction: ${finalizeTx.hash}\n`);
      
      // Verify
      const updatedOwner = await wr.walletOwner();
      console.log(`Updated Wallet Owner: ${updatedOwner}`);
      if (updatedOwner.toLowerCase() === newWalletOwner.toLowerCase()) {
        console.log("✓ Successfully updated wallet owner!");
      } else {
        console.log("⚠️  Update may not have completed correctly");
      }
    } else {
      const delaySeconds = governanceDelay.toNumber();
      const delayMinutes = Math.floor(delaySeconds / 60);
      console.log(`⏳ Wait ${delaySeconds} seconds (${delayMinutes} minutes) before finalizing`);
      console.log(`\nThen run:`);
      console.log(`  npx hardhat run scripts/finalize-wallet-owner-update.js --network development`);
    }
  } catch (error) {
    if (error.message.includes("already initialized")) {
      console.log("Wallet owner is already initialized. Using update flow...");
      // Try update flow
      const beginTx = await gov.connect(deployer).beginWalletOwnerUpdate(newWalletOwner);
      await beginTx.wait();
      console.log("Update initiated. Finalizing...");
      const finalizeTx = await gov.connect(deployer).finalizeWalletOwnerUpdate();
      await finalizeTx.wait();
      console.log("✓ Updated!");
    } else {
      throw error;
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });


