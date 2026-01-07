import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * Get the exact revert reason for approveDkgResult
 */
async function main() {
  const WalletRegistry = await hre.deployments.get("WalletRegistry")
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address)

  // Get DKG result from event
  const filter = wr.filters.DkgResultSubmitted()
  const events = await wr.queryFilter(filter, -2000)
  if (events.length === 0) {
    console.error("No events found")
    process.exit(1)
  }

  const latestEvent = events[events.length - 1]
  const result = latestEvent.args.result
  
  const [deployer] = await ethers.getSigners()
  const wrConnected = wr.connect(deployer)
  
  console.log("Attempting to get revert reason...")
  console.log("")
  
  try {
    // Try with callStatic to get revert reason
    await wrConnected.callStatic.approveDkgResult(result)
    console.log("✅ Call would succeed!")
  } catch (error: any) {
    console.log("❌ Call failed:")
    console.log(`   Message: ${error.message}`)
    
    if (error.reason) {
      console.log(`   Reason: ${error.reason}`)
    }
    
    // Try to decode the error data
    if (error.data) {
      console.log(`   Data: ${error.data}`)
      
      // Common error signatures
      const errors = {
        "Result under approval is different than the submitted one": ethers.utils.id("Result under approval is different than the submitted one").slice(0, 10),
        "Sortition pool unlocked": ethers.utils.id("Sortition pool unlocked").slice(0, 10),
        "Only the DKG result submitter can approve": ethers.utils.id("Only the DKG result submitter can approve").slice(0, 10),
        "DKG result challenge period has not passed": ethers.utils.id("DKG result challenge period has not passed").slice(0, 10),
        "DKG result submitter precedence period has not passed": ethers.utils.id("DKG result submitter precedence period has not passed").slice(0, 10),
      }
      
      for (const [errorMsg, sig] of Object.entries(errors)) {
        if (error.data.startsWith(sig)) {
          console.log("")
          console.log(`🔍 MATCHED ERROR: ${errorMsg}`)
          break
        }
      }
    }
    
    // Try to get more details using provider
    try {
      const tx = await wrConnected.populateTransaction.approveDkgResult(result)
      const result2 = await ethers.provider.call(tx)
      console.log(`   Raw result: ${result2}`)
    } catch (e2: any) {
      console.log(`   Provider call error: ${e2.message}`)
    }
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
