import { ethers } from "hardhat"

async function main() {
  const wr = await ethers.getContractAt(
    "WalletRegistry",
    "0xd49141e044801DEE237993deDf9684D59fafE2e6"
  )
  
  const params = await wr.dkgParameters()
  console.log("DKG Parameters:")
  console.log("  Result Submission Timeout:", params.resultSubmissionTimeout.toString(), "blocks")
  
  // Get DKG data
  const dkgData = await wr.dkgData()
  console.log("\nDKG Data:")
  console.log("  Start Block:", dkgData.startBlock.toString())
  console.log("  Result Submission Start Block Offset:", dkgData.resultSubmissionStartBlockOffset.toString())
  
  const currentBlock = await ethers.provider.getBlockNumber()
  console.log("  Current Block:", currentBlock)
  
  const timeoutBlock = dkgData.startBlock.add(dkgData.resultSubmissionStartBlockOffset).add(params.resultSubmissionTimeout)
  console.log("  Timeout Block:", timeoutBlock.toString())
  const blocksUntilTimeout = timeoutBlock.sub(currentBlock)
  console.log("  Blocks until timeout:", blocksUntilTimeout.toString())
  
  const hasTimedOut = await wr.hasDkgTimedOut()
  console.log("\nhasDkgTimedOut():", hasTimedOut)
  
  const state = await wr.getWalletCreationState()
  console.log("State:", state.toString(), "(0=IDLE, 1=AWAITING_SEED, 2=AWAITING_RESULT, 3=CHALLENGE)")
}

main().catch(console.error)
