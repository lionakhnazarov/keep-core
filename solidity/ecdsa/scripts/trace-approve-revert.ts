import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * Trace the approveDkgResult transaction to see exactly where it reverts
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
  
  console.log("Attempting approval with trace...")
  console.log("")
  
  try {
    // Try to estimate gas first to see the error
    const gasEstimate = await wrConnected.estimateGas.approveDkgResult(result)
    console.log(`Gas estimate: ${gasEstimate.toString()}`)
    
    // If estimate succeeds, try the actual transaction
    const tx = await wrConnected.approveDkgResult(result)
    console.log(`Transaction hash: ${tx.hash}`)
    const receipt = await tx.wait()
    console.log(`✅ Success! Block: ${receipt.blockNumber}`)
    
  } catch (error: any) {
    console.error("Transaction failed:")
    console.error(`  Message: ${error.message}`)
    
    if (error.reason) {
      console.error(`  Reason: ${error.reason}`)
    }
    
    if (error.data) {
      console.error(`  Data: ${error.data}`)
      
      // Try to decode common errors
      const errorSig1 = ethers.utils.id("Sortition pool unlocked").slice(0, 10)
      const errorSig2 = ethers.utils.id("Result under approval is different than the submitted one").slice(0, 10)
      const errorSig3 = ethers.utils.id("Only the DKG result submitter can approve").slice(0, 10)
      
      if (error.data.startsWith(errorSig1)) {
        console.error("")
        console.error("❌ ERROR: Sortition pool is already unlocked!")
      } else if (error.data.startsWith(errorSig2)) {
        console.error("")
        console.error("❌ ERROR: Hash mismatch!")
      } else if (error.data.startsWith(errorSig3)) {
        console.error("")
        console.error("❌ ERROR: Precedence period not passed!")
      }
    }
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
