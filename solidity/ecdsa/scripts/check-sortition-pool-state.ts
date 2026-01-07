import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * Check the sortition pool state to understand why unlock() is failing
 */
async function main() {
  const WalletRegistry = await hre.deployments.get("WalletRegistry")
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address)

  console.log("==========================================")
  console.log("Check Sortition Pool State")
  console.log("==========================================")
  console.log("")
  console.log(`WalletRegistry: ${WalletRegistry.address}`)
  console.log("")

  // Get sortition pool address from WalletRegistry
  try {
    const sortitionPoolAddress = await wr.sortitionPool()
    console.log(`SortitionPool Address: ${sortitionPoolAddress}`)
    console.log("")

    // Try to get the SortitionPool contract
    // Note: We need to check what functions are available
    const sortitionPoolCode = await ethers.provider.getCode(sortitionPoolAddress)
    console.log(`SortitionPool Code Length: ${sortitionPoolCode.length} bytes`)
    console.log("")

    if (sortitionPoolCode === "0x") {
      console.log("❌ ERROR: No code at sortition pool address!")
      process.exit(1)
    }

    // Try to call isLocked() if it exists
    try {
      const sortitionPool = await ethers.getContractAt("SortitionPool", sortitionPoolAddress)
      
      // Try common function names
      const functions = [
        "isLocked",
        "locked",
        "lockStatus",
        "getLockStatus",
      ]
      
      for (const funcName of functions) {
        try {
          const result = await sortitionPool[funcName]()
          console.log(`✓ ${funcName}(): ${result}`)
        } catch (e) {
          // Function doesn't exist, skip
        }
      }
      
      console.log("")
      
      // Try to check if unlock() requires specific permissions
      // Check who can call unlock - might need to check owner or authorized addresses
      try {
        const owner = await sortitionPool.owner()
        console.log(`SortitionPool Owner: ${owner}`)
        console.log(`WalletRegistry Address: ${WalletRegistry.address}`)
        console.log(`Can WalletRegistry unlock? ${owner.toLowerCase() === WalletRegistry.address.toLowerCase() ? "✅ YES (owner)" : "❌ NO (not owner)"}`)
      } catch (e) {
        // owner() might not exist
      }
      
      // Try to check authorized addresses
      try {
        const authorizedOperators = await sortitionPool.authorizedOperators(WalletRegistry.address)
        console.log(`WalletRegistry authorized: ${authorizedOperators}`)
      } catch (e) {
        // Function might not exist
      }
      
    } catch (e: any) {
      console.log("Could not load SortitionPool contract:")
      console.log(`  ${e.message}`)
      console.log("")
      console.log("Trying to decode unlock() call directly...")
      
      // Try to call unlock() directly to see the error
      try {
        const [deployer] = await ethers.getSigners()
        const unlockData = ethers.utils.id("unlock()").slice(0, 10)
        
        const result = await deployer.call({
          to: sortitionPoolAddress,
          data: unlockData,
        })
        console.log(`unlock() call result: ${result}`)
      } catch (callError: any) {
        console.log(`unlock() call error: ${callError.message}`)
        if (callError.data) {
          console.log(`Error data: ${callError.data}`)
          
          // Try to decode common error messages
          const commonErrors = [
            "Pool is not locked",
            "Caller is not authorized",
            "Only owner can unlock",
            "Pool must be locked",
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
    console.error("Error checking sortition pool:")
    console.error(`  ${e.message}`)
    process.exit(1)
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

