import { ethers } from "hardhat"
import hre from "hardhat"

async function main() {
  const { deployments } = hre
  
  const WalletRegistry = await deployments.get("WalletRegistry")
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address)
  
  console.log("==========================================")
  console.log("DKG Approval Status Diagnostic")
  console.log("==========================================")
  console.log(`WalletRegistry: ${WalletRegistry.address}`)
  console.log("")
  
  // Get current block
  const currentBlock = await ethers.provider.getBlockNumber()
  console.log(`Current Block: ${currentBlock}`)
  console.log("")
  
  // Check DKG state
  try {
    const state = await wr.getWalletCreationState()
    const stateNames = ["IDLE", "AWAITING_SEED", "AWAITING_RESULT", "CHALLENGE"]
    console.log(`1. DKG State: ${stateNames[state]} (${state})`)
    
    if (state !== 3) { // CHALLENGE = 3
      console.log("   ⚠️  WARNING: DKG is not in CHALLENGE state!")
      console.log("   Approval can only happen in CHALLENGE state.")
      return
    }
  } catch (error: any) {
    console.log(`1. DKG State: Error - ${error.message}`)
    return
  }
  
  // Get DKG parameters
  let params: any
  try {
    params = await wr.dkgParameters()
    console.log("")
    console.log("2. DKG Parameters:")
    console.log(`   - Challenge Period Length: ${params.resultChallengePeriodLength} blocks`)
    console.log(`   - Submitter Precedence Period: ${params.submitterPrecedencePeriodLength} blocks`)
  } catch (error: any) {
    console.log(`2. DKG Parameters: Error - ${error.message}`)
    return
  }
  
  // Get submitted result info
  try {
    // Try to get the submitted result hash from events
    const filter = wr.filters.DkgResultSubmitted()
    const events = await wr.queryFilter(filter, -1000) // Last 1000 blocks
    
    if (events.length === 0) {
      console.log("")
      console.log("3. No DKG result submitted found in recent blocks")
      return
    }
    
    const latestEvent = events[events.length - 1]
    const submissionBlock = latestEvent.blockNumber
    const resultHash = latestEvent.args.resultHash
    
    console.log("")
    console.log("3. Latest Submitted DKG Result:")
    console.log(`   - Submission Block: ${submissionBlock}`)
    console.log(`   - Result Hash: ${resultHash}`)
    console.log(`   - Blocks since submission: ${currentBlock - submissionBlock}`)
    
    const challengePeriodEnd = submissionBlock + Number(params.resultChallengePeriodLength)
    const precedencePeriodEnd = challengePeriodEnd + Number(params.submitterPrecedencePeriodLength)
    
    console.log("")
    console.log("4. Approval Timing:")
    console.log(`   - Challenge Period End Block: ${challengePeriodEnd}`)
    console.log(`   - Precedence Period End Block: ${precedencePeriodEnd}`)
    console.log(`   - Current Block: ${currentBlock}`)
    
    if (currentBlock <= challengePeriodEnd) {
      const blocksRemaining = challengePeriodEnd - currentBlock + 1
      console.log("")
      console.log("   ⚠️  ERROR: Challenge period has not passed yet!")
      console.log(`   Need to wait ${blocksRemaining} more blocks`)
      console.log(`   (~${Math.ceil(blocksRemaining * 15 / 60)} minutes at 15s/block)`)
    } else if (currentBlock <= precedencePeriodEnd) {
      const blocksRemaining = precedencePeriodEnd - currentBlock + 1
      console.log("")
      console.log("   ⚠️  WARNING: In precedence period!")
      console.log(`   Only the submitter can approve for ${blocksRemaining} more blocks`)
      console.log(`   (~${Math.ceil(blocksRemaining * 15 / 60)} minutes at 15s/block)`)
    } else {
      console.log("")
      console.log("   ✅ Challenge period has passed - approval allowed")
    }
    
    // Check if already approved
    const approvedFilter = wr.filters.DkgResultApproved()
    const approvedEvents = await wr.queryFilter(approvedFilter, submissionBlock)
    
    if (approvedEvents.length > 0) {
      console.log("")
      console.log("   ✅ DKG result already approved!")
      approvedEvents.forEach((event, i) => {
        const approver = event.args.approver || event.args[0] || "unknown"
        console.log(`   Approval ${i + 1}: Block ${event.blockNumber}, Approver: ${approver}`)
        console.log(`   Result Hash: ${event.args.resultHash || event.args[0] || "unknown"}`)
      })
      console.log("")
      console.log("   If DKG is still in CHALLENGE state, this might be a state sync issue.")
      console.log("   Try checking wallet creation state again or wait for next block.")
    } else {
      console.log("")
      console.log("   ⚠️  DKG result NOT yet approved")
      console.log("   Operators should approve the result to complete DKG.")
    }
    
    // Get submitter info
    try {
      const seed = latestEvent.args.seed
      const result = latestEvent.args.result
      console.log("")
      console.log("5. DKG Result Details:")
      console.log(`   - Seed: ${seed}`)
      if (result && result.submitterMemberIndex !== undefined) {
        console.log(`   - Submitter Member Index: ${result.submitterMemberIndex}`)
      }
    } catch (e) {
      // Some events might not have all fields
      console.log("")
      console.log("5. DKG Result Details:")
      console.log(`   - Seed: ${latestEvent.args.seed}`)
    }
    
  } catch (error: any) {
    console.log(`3. Error getting submitted result: ${error.message}`)
  }
  
  console.log("")
  console.log("==========================================")
}

main().catch(console.error)

