const hre = require("hardhat");

async function main() {
  const { deployments } = hre;
  const WalletRegistry = await deployments.get("WalletRegistry");
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address);
  
  const randomBeaconAddress = await wr.randomBeacon();
  console.log("WalletRegistry RandomBeacon:", randomBeaconAddress);
  
  const rb = await ethers.getContractAt(
    ["function authorizedRequesters(address) view returns (bool)", 
     "function requestRelayEntry(address) external",
     "function owner() view returns (address)"],
    randomBeaconAddress
  );
  
  const isAuth = await rb.authorizedRequesters(WalletRegistry.address);
  console.log("WalletRegistry authorized:", isAuth);
  
  if (!isAuth) {
    console.log("\n❌ WalletRegistry is NOT authorized!");
    const owner = await rb.owner();
    console.log("RandomBeacon owner:", owner);
    console.log("\nTo authorize:");
    console.log(`  cast send ${randomBeaconAddress} "setRequesterAuthorization(address,bool)" ${WalletRegistry.address} true --rpc-url http://localhost:8545 --unlocked --from ${owner}`);
    return;
  }
  
  console.log("\n✓ WalletRegistry is authorized");
  console.log("\nTesting requestRelayEntry call...");
  
  // Simulate WalletRegistry calling requestRelayEntry
  // The msg.sender will be WalletRegistry.address
  try {
    // Use callStatic to simulate
    await rb.callStatic.requestRelayEntry(WalletRegistry.address, {
      from: WalletRegistry.address
    });
    console.log("✓ requestRelayEntry call would succeed");
  } catch (e) {
    console.log("❌ requestRelayEntry would fail:");
    console.log("  Error:", e.reason || e.message);
    
    // Try to understand the error better
    if (e.reason?.includes("authorized")) {
      console.log("\n⚠️  Authorization issue - but we checked and it's authorized!");
      console.log("This might be a simulation issue. Try the actual call.");
    }
  }
  
  // Now try the actual requestNewWallet
  console.log("\n" + "=".repeat(50));
  console.log("Testing requestNewWallet()...");
  console.log("=".repeat(50));
  
  const accounts = await ethers.getSigners();
  const walletOwnerAccount = accounts.find(a => 
    a.address.toLowerCase() === "0x7966c178f466b060aaeb2b91e9149a5fb2ec9c53".toLowerCase()
  );
  
  if (!walletOwnerAccount) {
    console.log("❌ Wallet owner account not found in signers");
    return;
  }
  
  console.log("Using wallet owner:", walletOwnerAccount.address);
  
  const dkgState = await wr.getWalletCreationState();
  if (dkgState !== 0) {
    console.log(`⚠️  DKG state is ${dkgState}, not IDLE`);
    return;
  }
  
  console.log("DKG state: IDLE - ready to request");
  console.log("\nCalling requestNewWallet()...");
  
  try {
    const tx = await wr.connect(walletOwnerAccount).requestNewWallet({ gasLimit: 1000000 });
    console.log("Transaction hash:", tx.hash);
    const receipt = await tx.wait();
    
    if (receipt.status === 1) {
      console.log("✓ SUCCESS! Wallet request submitted!");
      console.log("Block:", receipt.blockNumber);
      console.log("\nDKG should start soon. Monitor logs for DKG activity.");
    } else {
      console.log("❌ Transaction reverted");
    }
  } catch (error) {
    console.log("❌ Error:", error.message);
    if (error.reason) {
      console.log("Reason:", error.reason);
    }
    
    // Try to get more details
    try {
      await wr.connect(walletOwnerAccount).callStatic.requestNewWallet({ gasLimit: 1000000 });
    } catch (staticError) {
      console.log("\nStatic call error:", staticError.reason || staticError.message);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

