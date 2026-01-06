import { ethers } from "hardhat"
import hre from "hardhat"

async function main() {
  console.log("==========================================")
  console.log("Fix RandomBeacon & Authorization")
  console.log("==========================================")
  console.log("")

  // Get WalletRegistry
  const WalletRegistry = await hre.deployments.get("WalletRegistry")
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address)

  // Get RandomBeaconChaosnet
  const fs = require("fs")
  const path = require("path")
  const chaosnetPath = path.resolve(__dirname, "../../random-beacon/deployments/development/RandomBeaconChaosnet.json")
  
  if (!fs.existsSync(chaosnetPath)) {
    console.error("Error: RandomBeaconChaosnet deployment not found")
    console.error("Deploy RandomBeaconChaosnet first:")
    console.error("  cd solidity/random-beacon && npx hardhat deploy --network development")
    process.exit(1)
  }

  const chaosnetData = JSON.parse(fs.readFileSync(chaosnetPath, "utf8"))
  const randomBeaconChaosnetAddress = chaosnetData.address

  console.log(`WalletRegistry: ${WalletRegistry.address}`)
  console.log(`RandomBeaconChaosnet: ${randomBeaconChaosnetAddress}`)
  console.log("")

  // Check current RandomBeacon
  const currentRandomBeacon = await wr.randomBeacon()
  console.log(`Current RandomBeacon: ${currentRandomBeacon}`)
  console.log(`Expected RandomBeaconChaosnet: ${randomBeaconChaosnetAddress}`)
  console.log("")

  // Check if RandomBeacon needs to be upgraded
  if (currentRandomBeacon.toLowerCase() !== randomBeaconChaosnetAddress.toLowerCase()) {
    console.log("Step 1: Upgrading RandomBeacon in WalletRegistry...")
    
    try {
      const WalletRegistryGovernance = await hre.deployments.get("WalletRegistryGovernance")
      const wrGov = await ethers.getContractAt(
        "WalletRegistryGovernance",
        WalletRegistryGovernance.address
      )

      const { deployer, governance } = await hre.getNamedAccounts()
      const owner = await wrGov.owner()
      const signerAddress = owner.toLowerCase() === deployer.toLowerCase() ? deployer : governance
      const signer = await ethers.getSigner(signerAddress)

      console.log(`Using account: ${signerAddress} (governance owner: ${owner})`)

      const wrGovConnected = wrGov.connect(signer)
      const tx = await wrGovConnected.upgradeRandomBeacon(randomBeaconChaosnetAddress)
      console.log(`Transaction: ${tx.hash}`)
      await tx.wait()
      console.log("✓ RandomBeacon upgraded!")
    } catch (error: any) {
      console.error(`✗ Error upgrading RandomBeacon: ${error.message}`)
      console.error("")
      console.error("Try running the deployment script:")
      console.error("  cd solidity/ecdsa")
      console.error("  npx hardhat deploy --tags UpgradeRandomBeaconChaosnet --network development")
      process.exit(1)
    }
    console.log("")
  } else {
    console.log("✓ RandomBeacon is already set correctly")
    console.log("")
  }

  // Check authorization
  console.log("Step 2: Checking RandomBeaconChaosnet authorization...")
  const RandomBeaconChaosnet = await ethers.getContractAt(
    ["function authorizedRequesters(address) view returns (bool)", "function owner() view returns (address)", "function setRequesterAuthorization(address, bool)"],
    randomBeaconChaosnetAddress
  )

  const isAuthorized = await RandomBeaconChaosnet.authorizedRequesters(WalletRegistry.address)
  console.log(`WalletRegistry authorized: ${isAuthorized}`)
  console.log("")

  if (!isAuthorized) {
    console.log("Step 3: Authorizing WalletRegistry in RandomBeaconChaosnet...")
    
    const owner = await RandomBeaconChaosnet.owner()
    console.log(`RandomBeaconChaosnet owner: ${owner}`)

    const { deployer } = await hre.getNamedAccounts()
    const ownerSigner = await ethers.getSigner(owner)
    
    if (owner.toLowerCase() !== deployer.toLowerCase()) {
      console.warn(`⚠ Owner (${owner}) != deployer (${deployer})`)
      console.warn("You'll need to authorize manually or use the owner account")
      console.log("")
      console.log("To authorize manually:")
      console.log(`  RandomBeaconChaosnet.setRequesterAuthorization(${WalletRegistry.address}, true)`)
      console.log(`  Using account: ${owner}`)
      console.log("")
    } else {
      try {
        const rbChaosnetConnected = RandomBeaconChaosnet.connect(ownerSigner)
        const tx = await rbChaosnetConnected.setRequesterAuthorization(WalletRegistry.address, true)
        console.log(`Transaction: ${tx.hash}`)
        await tx.wait()
        console.log("✓ WalletRegistry authorized!")
      } catch (error: any) {
        console.error(`✗ Error authorizing: ${error.message}`)
        console.error("")
        console.error("Try running:")
        console.error("  cd solidity/ecdsa")
        console.error("  npx hardhat run scripts/authorize-wallet-registry-in-beacon.ts --network development")
        process.exit(1)
      }
    }
    console.log("")
  } else {
    console.log("✓ WalletRegistry is already authorized")
    console.log("")
  }

  // Final verification
  console.log("Step 4: Final Verification")
  console.log("===========================")
  const finalRandomBeacon = await wr.randomBeacon()
  const finalIsAuthorized = await RandomBeaconChaosnet.authorizedRequesters(WalletRegistry.address)

  console.log(`RandomBeacon: ${finalRandomBeacon}`)
  console.log(`  Expected: ${randomBeaconChaosnetAddress}`)
  console.log(`  Match: ${finalRandomBeacon.toLowerCase() === randomBeaconChaosnetAddress.toLowerCase() ? "✓" : "✗"}`)
  console.log("")
  console.log(`Authorization: ${finalIsAuthorized ? "✓ Authorized" : "✗ Not authorized"}`)
  console.log("")

  if (finalRandomBeacon.toLowerCase() === randomBeaconChaosnetAddress.toLowerCase() && finalIsAuthorized) {
    console.log("==========================================")
    console.log("✅ SUCCESS! RandomBeacon is fixed!")
    console.log("==========================================")
    console.log("")
    console.log("Now try requesting a new wallet:")
    console.log("  cd solidity/ecdsa")
    console.log("  npx hardhat run scripts/request-new-wallet.ts --network development")
    console.log("")
  } else {
    console.error("==========================================")
    console.error("✗ Issues remain - fix them above")
    console.error("==========================================")
    process.exit(1)
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

