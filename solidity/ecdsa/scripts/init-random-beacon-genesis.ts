import { ethers } from "hardhat"
import hre from "hardhat"

async function main() {
  const { getNamedAccounts, deployments } = hre
  const { deployer } = await getNamedAccounts()
  
  // Get RandomBeacon address
  const fs = require("fs")
  const path = require("path")
  const rbPath = path.resolve(__dirname, "../../random-beacon/deployments/development/RandomBeacon.json")
  
  let randomBeaconAddress: string
  if (fs.existsSync(rbPath)) {
    const rbData = JSON.parse(fs.readFileSync(rbPath, "utf8"))
    randomBeaconAddress = rbData.address
  } else {
    // Try to get from deployments
    try {
      const RandomBeacon = await deployments.get("RandomBeacon")
      randomBeaconAddress = RandomBeacon.address
    } catch (e) {
      console.error("Error: RandomBeacon deployment not found")
      console.error("Please deploy RandomBeacon first:")
      console.error("  cd solidity/random-beacon && npx hardhat deploy --network development")
      process.exit(1)
    }
  }
  
  console.log("==========================================")
  console.log("Initializing RandomBeacon Genesis")
  console.log("==========================================")
  console.log(`RandomBeacon: ${randomBeaconAddress}`)
  console.log("")
  
  const RandomBeacon = await ethers.getContractAt(
    ["function genesis() external", "function numberOfActiveGroups() view returns (uint256)"],
    randomBeaconAddress
  )
  
  // Check current number of active groups
  try {
    const numGroups = await RandomBeacon.numberOfActiveGroups()
    console.log(`Current active groups: ${numGroups.toString()}`)
    
    if (numGroups.gt(0)) {
      console.log("✓ RandomBeacon already has active groups")
      return
    }
  } catch (e: any) {
    console.log(`⚠️  Could not check numberOfActiveGroups: ${e.message}`)
    console.log("   Proceeding with genesis() call...")
  }
  
  console.log("Calling RandomBeacon.genesis() to create initial group...")
  console.log("Note: This requires operators to be in RandomBeacon's sortition pool")
  console.log("")
  
  const [signer] = await ethers.getSigners()
  console.log(`Using account: ${signer.address}`)
  
  try {
    const tx = await RandomBeacon.connect(signer).genesis({ gasLimit: 500000 })
    console.log(`Transaction submitted: ${tx.hash}`)
    const receipt = await tx.wait()
    
    if (receipt.status === 1) {
      console.log("✓ Genesis completed successfully!")
      console.log(`   Transaction confirmed in block: ${receipt.blockNumber}`)
      console.log("")
      console.log("You can now trigger DKG via WalletRegistry.requestNewWallet()")
    } else {
      throw new Error("Transaction reverted")
    }
  } catch (error: any) {
    console.error(`Error calling genesis(): ${error.message}`)
    if (error.message?.includes("Not awaiting genesis")) {
      console.error("   RandomBeacon already has active groups or DKG is in progress")
    } else if (error.message?.includes("pool")) {
      console.error("   RandomBeacon sortition pool may be empty or locked")
      console.error("   Make sure RandomBeacon operators are registered and in the sortition pool")
    }
    throw error
  }
}

main().catch(console.error)
