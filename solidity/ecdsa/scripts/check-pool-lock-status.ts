import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * Check if the sortition pool is locked and why unlock() might fail
 */
async function main() {
  const WalletRegistry = await hre.deployments.get("WalletRegistry")
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address)

  console.log("==========================================")
  console.log("Check Sortition Pool Lock Status")
  console.log("==========================================")
  console.log("")
  console.log(`WalletRegistry: ${WalletRegistry.address}`)
  console.log("")

  // Get sortition pool address
  const sortitionPoolAddress = await wr.sortitionPool()
  console.log(`SortitionPool Address: ${sortitionPoolAddress}`)
  console.log("")

  // Check DKG state
  const dkgState = await wr.getWalletCreationState()
  console.log(`DKG State: ${dkgState} (3 = CHALLENGE)`)
  console.log("")

  // Try to check if pool is locked
  // The SortitionPool contract should have isLocked() function
  try {
    // Create a minimal interface for SortitionPool
    const sortitionPoolABI = [
      "function isLocked() view returns (bool)",
      "function unlock()",
      "function lock()",
      "function owner() view returns (address)",
    ]
    
    const sortitionPool = new ethers.Contract(
      sortitionPoolAddress,
      sortitionPoolABI,
      ethers.provider
    )
    
    const isLocked = await sortitionPool.isLocked()
    console.log(`Pool isLocked(): ${isLocked}`)
    console.log("")
    
    if (!isLocked) {
      console.log("⚠️  WARNING: Pool is NOT locked!")
      console.log("   unlock() might fail if pool is not locked")
      console.log("   This could be the issue!")
    } else {
      console.log("✅ Pool is locked (as expected)")
      console.log("")
      console.log("Checking if WalletRegistry can unlock...")
      
      // Check owner
      try {
        const owner = await sortitionPool.owner()
        console.log(`SortitionPool Owner: ${owner}`)
        console.log(`WalletRegistry: ${WalletRegistry.address}`)
        
        if (owner.toLowerCase() === WalletRegistry.address.toLowerCase()) {
          console.log("✅ WalletRegistry is the owner - should be able to unlock")
        } else {
          console.log("❌ WalletRegistry is NOT the owner")
          console.log("   unlock() might require owner permissions")
        }
      } catch (e) {
        console.log("Could not check owner (function might not exist)")
      }
      
      // Try a static call to unlock to see the error
      console.log("")
      console.log("Testing unlock() call...")
      try {
        const [deployer] = await ethers.getSigners()
        const unlockData = ethers.utils.id("unlock()").slice(0, 10)
        
        // Try as WalletRegistry
        const result = await ethers.provider.call({
          from: WalletRegistry.address,
          to: sortitionPoolAddress,
          data: unlockData,
        })
        console.log(`unlock() call succeeded: ${result}`)
      } catch (callError: any) {
        console.log(`unlock() call failed: ${callError.message}`)
        if (callError.data && callError.data !== "0x") {
          console.log(`Error data: ${callError.data}`)
          
          // Try to decode common error messages
          const commonErrors = [
            "Pool is not locked",
            "Caller is not authorized",
            "Only owner can unlock",
            "Pool must be locked",
            "Unauthorized",
          ]
          
          for (const errorMsg of commonErrors) {
            const errorSig = ethers.utils.id(errorMsg).slice(0, 10)
            if (callError.data.startsWith(errorSig)) {
              console.log(`Likely error: ${errorMsg}`)
              break
            }
          }
        }
      }
    }
    
  } catch (e: any) {
    console.error("Error checking pool status:")
    console.error(`  ${e.message}`)
    process.exit(1)
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

