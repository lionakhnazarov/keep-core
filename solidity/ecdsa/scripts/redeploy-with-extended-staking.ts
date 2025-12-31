import { HardhatRuntimeEnvironment } from "hardhat/types"

/**
 * Redeploy WalletRegistry and RandomBeacon with ExtendedTokenStaking
 * This is needed because WalletRegistry's staking address is set in constructor
 */
async function main() {
  const hre: HardhatRuntimeEnvironment = require("hardhat")
  const { deployments, helpers } = hre
  
  if (hre.network.name !== "development") {
    console.log("This script only works for development network")
    process.exit(1)
  }
  
  console.log("=== Redeploying Contracts with ExtendedTokenStaking ===")
  console.log("")
  
  // Check ExtendedTokenStaking exists
  const extendedTS = await deployments.getOrNull("ExtendedTokenStaking")
  if (!extendedTS) {
    console.log("❌ ExtendedTokenStaking not found. Deploy it first:")
    console.log("   npx hardhat deploy --tags ExtendedTokenStaking --network development")
    process.exit(1)
  }
  
  console.log(`Using ExtendedTokenStaking at ${extendedTS.address}`)
  console.log("")
  console.log("⚠️  This will delete existing WalletRegistry and RandomBeacon deployments")
  console.log("   and redeploy them with ExtendedTokenStaking")
  console.log("")
  console.log("Press Ctrl+C to cancel, or wait 5 seconds to continue...")
  await new Promise(resolve => setTimeout(resolve, 5000))
  
  // Delete existing deployments
  console.log("Deleting existing deployments...")
  await deployments.delete("WalletRegistry")
  await deployments.delete("WalletRegistryGovernance")
  console.log("✓ Deleted WalletRegistry and WalletRegistryGovernance")
  
  // Also delete RandomBeacon from random-beacon package if needed
  const randomBeaconPath = require("path").resolve(
    __dirname,
    "../../random-beacon/deployments/development/RandomBeacon.json"
  )
  const fs = require("fs")
  if (fs.existsSync(randomBeaconPath)) {
    console.log("⚠️  RandomBeacon deployment found. You may need to redeploy it too.")
    console.log("   Run: cd ../random-beacon && npx hardhat deploy --network development")
  }
  
  console.log("")
  console.log("✅ Ready to redeploy. Run:")
  console.log("   npx hardhat deploy --tags WalletRegistry --network development")
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
