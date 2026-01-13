const hre = require("hardhat");

async function main() {
  const { deployments } = hre;
  const WalletRegistry = await deployments.get("WalletRegistry");
  const RandomBeacon = await deployments.get("RandomBeacon");
  
  const rb = await ethers.getContractAt("RandomBeacon", RandomBeacon.address);
  const isAuthorized = await rb.isRequesterAuthorized(WalletRegistry.address);
  
  console.log("WalletRegistry:", WalletRegistry.address);
  console.log("RandomBeacon:", RandomBeacon.address);
  console.log("WalletRegistry authorized:", isAuthorized);
  
  if (!isAuthorized) {
    console.log("\n⚠️  WalletRegistry is NOT authorized in RandomBeacon!");
    console.log("This prevents requestNewWallet() from working.");
    console.log("\nTo fix, run:");
    console.log("  npx hardhat run scripts/authorize-wallet-registry-in-beacon.ts --network development");
  } else {
    console.log("\n✓ WalletRegistry is authorized");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });


