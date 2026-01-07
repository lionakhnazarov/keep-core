import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * Decode the actual revert reason from approval transaction
 */
async function main() {
  const WalletRegistry = await hre.deployments.get("WalletRegistry")
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address)

  // Get submission event
  const filter = wr.filters.DkgResultSubmitted()
  const currentBlock = await ethers.provider.getBlockNumber()
  const fromBlock = Math.max(0, currentBlock - 5000)
  const events = await wr.queryFilter(filter, fromBlock, currentBlock)
  
  if (events.length === 0) {
    console.error("Error: Could not find DKG result submission event")
    process.exit(1)
  }

  const latestEvent = events[events.length - 1]
  const eventResult = latestEvent.args.result
  
  console.log("==========================================")
  console.log("Decode Approval Revert Reason")
  console.log("==========================================")
  console.log("")

  const [deployer] = await ethers.getSigners()
  const wrConnected = wr.connect(deployer)
  
  // Try a static call first to get the revert reason
  console.log("Attempting static call to get revert reason...")
  console.log("")
  
  try {
    // Static call won't actually execute, but will show the revert reason
    await wrConnected.callStatic.approveDkgResult(eventResult)
    console.log("✅ Static call succeeded - approval should work!")
  } catch (error: any) {
    console.log("❌ Static call failed - this is the revert reason:")
    console.log("")
    
    // Try to decode the error
    if (error.data) {
      console.log(`Raw error data: ${error.data}`)
      console.log("")
      
      // Try to decode as a custom error
      try {
        const decoded = wr.interface.parseError(error.data)
        console.log(`Decoded error: ${decoded.name}`)
        console.log(`  Args: ${JSON.stringify(decoded.args, null, 2)}`)
      } catch (e) {
        // Try to decode as a revert string
        try {
          // Revert strings are encoded as: Error(string)
          const errorSig = ethers.utils.id("Error(string)").slice(0, 10)
          if (error.data.startsWith(errorSig)) {
            const decoded = ethers.utils.defaultAbiCoder.decode(
              ["string"],
              "0x" + error.data.slice(10)
            )
            console.log(`Revert reason: ${decoded[0]}`)
          } else {
            console.log("Could not decode error - trying common error signatures...")
            
            // Check common error signatures
            const commonErrors = [
              { name: "Result under approval is different than the submitted one", sig: "0x" + ethers.utils.id("Result under approval is different than the submitted one").slice(0, 10) },
              { name: "Current state is not CHALLENGE", sig: "0x" + ethers.utils.id("Current state is not CHALLENGE").slice(0, 10) },
              { name: "Challenge period has not passed yet", sig: "0x" + ethers.utils.id("Challenge period has not passed yet").slice(0, 10) },
              { name: "Only the DKG result submitter can approve the result at this moment", sig: "0x" + ethers.utils.id("Only the DKG result submitter can approve the result at this moment").slice(0, 10) },
            ]
            
            for (const err of commonErrors) {
              if (error.data.startsWith(err.sig)) {
                console.log(`Likely error: ${err.name}`)
                break
              }
            }
          }
        } catch (e2) {
          console.log("Could not decode as revert string either")
          console.log(`Error: ${e2}`)
        }
      }
    }
    
    if (error.reason) {
      console.log("")
      console.log(`Error reason: ${error.reason}`)
    }
    
    if (error.message) {
      console.log("")
      console.log(`Error message: ${error.message}`)
    }
  }
  
  console.log("")
  console.log("Checking DKG state and timing...")
  console.log("")
  
  const state = await wr.getWalletCreationState()
  console.log(`Current DKG State: ${state}`)
  
  const submissionBlock = latestEvent.blockNumber
  const params = await wr.dkgParameters()
  const challengeEnd = submissionBlock + Number(params.resultChallengePeriodLength)
  const precedenceEnd = challengeEnd + Number(params.submitterPrecedencePeriodLength)
  
  console.log(`Submission Block: ${submissionBlock}`)
  console.log(`Current Block: ${currentBlock}`)
  console.log(`Challenge period ends: ${challengeEnd}`)
  console.log(`Precedence period ends: ${precedenceEnd}`)
  console.log("")
  
  if (currentBlock < challengeEnd) {
    console.log("⚠️  Challenge period has not ended")
  } else if (currentBlock < precedenceEnd) {
    console.log("⚠️  Still in precedence period - only submitter can approve")
    console.log(`   Submitter member index: ${eventResult.submitterMemberIndex.toString()}`)
  } else {
    console.log("✓ Timing is correct - anyone can approve")
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

