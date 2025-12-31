import { HardhatRuntimeEnvironment } from "hardhat/types"

async function main() {
  const hre: HardhatRuntimeEnvironment = require("hardhat")
  const { ethers, helpers } = hre
  
  console.log("=== Checking RandomBeacon Sortition Pool ===")
  console.log("")
  
  const rb = await helpers.contracts.getContract("RandomBeacon")
  console.log("RandomBeacon address:", rb.address)
  
  try {
    const spAddr = await rb.sortitionPool()
    console.log("Sortition Pool Address:", spAddr)
    
    const code = await ethers.provider.getCode(spAddr)
    console.log("Sortition Pool Code Length:", code.length)
    
    if (code.length <= 2) {
      console.log("⚠️  Sortition pool has no code!")
      console.log("   This is the problem - RandomBeacon points to an address without code")
    } else {
      console.log("✓ Sortition pool exists and has code")
    }
  } catch (error: any) {
    console.log("❌ Error calling sortitionPool():", error.message)
  }
  
  // Check deployed sortition pool
  const deployedSP = await helpers.contracts.getContract("BeaconSortitionPool")
  console.log("")
  console.log("Deployed BeaconSortitionPool:", deployedSP.address)
  
  const deployedCode = await ethers.provider.getCode(deployedSP.address)
  if (deployedCode.length > 2) {
    console.log("✓ Deployed sortition pool exists")
  } else {
    console.log("⚠️  Deployed sortition pool has no code")
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
