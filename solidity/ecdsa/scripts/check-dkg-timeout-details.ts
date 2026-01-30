import { ethers } from "hardhat"
import hre from "hardhat"

async function main() {
  const { deployments } = hre
  
  const WalletRegistry = await deployments.get("WalletRegistry")
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address)
  
  console.log("==========================================")
  console.log("DKG Timeout Details")
  console.log("==========================================")
  console.log(`WalletRegistry: ${WalletRegistry.address}`)
  console.log("")
  
  const params = await wr.dkgParameters()
  console.log("DKG Parameters:")
  console.log("  Result Submission Timeout:", params.resultSubmissionTimeout.toString(), "blocks")
  console.log("  Seed Timeout:", params.seedTimeout.toString(), "blocks")
  console.log("  Result Challenge Period Length:", params.resultChallengePeriodLength.toString(), "blocks")
  
  // Get DKG start block from events
  console.log("\nDKG State:")
  const state = await wr.getWalletCreationState()
  const stateNames = ["IDLE", "AWAITING_SEED", "AWAITING_RESULT", "CHALLENGE"]
  console.log("  State:", stateNames[state], `(${state})`)
  
  const hasTimedOut = await wr.hasDkgTimedOut()
  console.log("  Has Timed Out:", hasTimedOut)
  
  const currentBlock = await ethers.provider.getBlockNumber()
  console.log("  Current Block:", currentBlock)
  
  // Query DkgStarted events to get the start block
  try {
    const filterDkgStarted = wr.filters.DkgStarted()
    const dkgStartedEvents = await wr.queryFilter(filterDkgStarted, -5000) // Last 5000 blocks
    
    if (dkgStartedEvents.length > 0) {
      const latestDkgStarted = dkgStartedEvents[dkgStartedEvents.length - 1]
      const startBlock = latestDkgStarted.blockNumber
      const seed = latestDkgStarted.args.seed
      
      console.log("\nLatest DKG Started Event:")
      console.log("  Start Block:", startBlock.toString())
      console.log("  Seed:", seed.toString())
      
      // Calculate timeout block (startBlock + resultSubmissionTimeout)
      const timeoutBlock = startBlock + Number(params.resultSubmissionTimeout)
      console.log("  Timeout Block:", timeoutBlock.toString())
      
      const blocksUntilTimeout = timeoutBlock - currentBlock
      if (blocksUntilTimeout > 0) {
        console.log("  Blocks until timeout:", blocksUntilTimeout.toString())
      } else {
        console.log("  Blocks until timeout:", blocksUntilTimeout.toString(), "(TIMED OUT)")
      }
    } else {
      console.log("\nNo DkgStarted events found in recent blocks")
      console.log("  DKG may not have started yet, or events are outside the query range")
    }
  } catch (error: any) {
    console.log("\nError querying DKG events:", error.message)
  }
  
  console.log("")
  console.log("==========================================")
}

main().catch(console.error)
