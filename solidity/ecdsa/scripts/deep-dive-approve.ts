import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * Deep dive into approveResult to find the exact failure point
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
  
  console.log("==========================================")
  console.log("Deep Dive: approveResult Analysis")
  console.log("==========================================")
  console.log("")
  
  // Check misbehaved members
  console.log("Misbehaved Members Analysis:")
  console.log(`  Count: ${result.misbehavedMembersIndices.length}`)
  
  if (result.misbehavedMembersIndices.length > 0) {
    const sortitionPoolAddress = await wr.sortitionPool()
    const sortitionPoolABI = [
      "function getIDOperator(uint32 id) view returns (address)",
    ]
    const sp = new ethers.Contract(sortitionPoolAddress, sortitionPoolABI, ethers.provider)
    
    for (let i = 0; i < result.misbehavedMembersIndices.length; i++) {
      const idx = result.misbehavedMembersIndices[i]
      const memberID = result.members[idx - 1]
      console.log(`  [${i}] Index: ${idx}, Member ID: ${memberID}`)
      
      try {
        const operator = await sp.getIDOperator(memberID)
        console.log(`      Operator: ${operator}`)
      } catch (e: any) {
        console.log(`      ❌ FAIL: getIDOperator failed: ${e.message}`)
      }
    }
  } else {
    console.log("  No misbehaved members")
  }
  
  console.log("")
  console.log("Attempting to call approveDkgResult with detailed error handling...")
  console.log("")
  
  const [deployer] = await ethers.getSigners()
  const wrConnected = wr.connect(deployer)
  
  try {
    // Try with increased gas limit
    const gasEstimate = await wrConnected.estimateGas.approveDkgResult(result)
    console.log(`Gas estimate: ${gasEstimate.toString()}`)
    
    const tx = await wrConnected.approveDkgResult(result, {
      gasLimit: gasEstimate.mul(120).div(100) // 20% buffer
    })
    console.log(`Transaction hash: ${tx.hash}`)
    const receipt = await tx.wait()
    console.log(`✅ SUCCESS! Block: ${receipt.blockNumber}`)
    
  } catch (error: any) {
    console.log("❌ Transaction failed:")
    console.log(`   Message: ${error.message}`)
    
    if (error.reason) {
      console.log(`   Reason: ${error.reason}`)
    }
    
    if (error.data) {
      console.log(`   Data: ${error.data}`)
      
      // Try to decode common errors
      const errorSig1 = ethers.utils.id("Result under approval is different than the submitted one").slice(0, 10)
      const errorSig2 = ethers.utils.id("Only the DKG result submitter can approve").slice(0, 10)
      const errorSig3 = ethers.utils.id("Challenge period has not passed yet").slice(0, 10)
      
      if (error.data.startsWith(errorSig1)) {
        console.log("")
        console.log("🔍 ERROR: Hash mismatch!")
      } else if (error.data.startsWith(errorSig2)) {
        console.log("")
        console.log("🔍 ERROR: Precedence period not passed!")
      } else if (error.data.startsWith(errorSig3)) {
        console.log("")
        console.log("🔍 ERROR: Challenge period not passed!")
      } else if (error.data === "0x") {
        console.log("")
        console.log("🔍 ERROR: Low-level revert (no error message)")
        console.log("   Possible causes:")
        console.log("   1. Array access out of bounds")
        console.log("   2. External call failure (getIDOperator)")
        console.log("   3. Arithmetic underflow/overflow")
        console.log("   4. Gas exhaustion")
      }
    }
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
