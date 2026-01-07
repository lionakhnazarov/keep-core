import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * Check precedence period and submitter
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
  const submissionBlock = latestEvent.blockNumber
  
  const [deployer] = await ethers.getSigners()
  
  console.log("==========================================")
  console.log("Checking Precedence Period")
  console.log("==========================================")
  console.log("")
  console.log(`Submission block: ${submissionBlock}`)
  console.log(`Current caller: ${deployer.address}`)
  console.log("")
  
  // Get sortition pool to find submitter operator
  const sortitionPoolAddress = await wr.sortitionPool()
  const sortitionPoolABI = [
    "function getIDOperator(uint32 id) view returns (address)",
  ]
  const sp = new ethers.Contract(sortitionPoolAddress, sortitionPoolABI, ethers.provider)
  
  const submitterIndex = result.submitterMemberIndex
  const memberID = result.members[submitterIndex.sub(1).toNumber()]
  const submitterOperator = await sp.getIDOperator(memberID)
  
  console.log(`Submitter member index: ${submitterIndex.toString()}`)
  console.log(`Submitter member ID: ${memberID}`)
  console.log(`Submitter operator: ${submitterOperator}`)
  console.log(`Current caller: ${deployer.address}`)
  console.log(`Match: ${submitterOperator.toLowerCase() === deployer.address.toLowerCase() ? "✅ YES" : "❌ NO"}`)
  console.log("")
  
  // Estimate precedence period (typically 200 blocks after challenge period)
  const currentBlock = await ethers.provider.getBlockNumber()
  const blocksSinceSubmission = currentBlock - submissionBlock
  
  console.log(`Current block: ${currentBlock}`)
  console.log(`Blocks since submission: ${blocksSinceSubmission}`)
  console.log("")
  console.log("Period estimates:")
  console.log("  - Challenge period: ~200 blocks")
  console.log("  - Precedence period: ~200 blocks after challenge period")
  console.log("  - Total: ~400 blocks from submission")
  console.log("")
  
  if (blocksSinceSubmission < 400) {
    console.log(`⚠️  Precedence period may not have passed yet`)
    console.log(`   Only submitter (${submitterOperator}) can approve`)
    
    if (submitterOperator.toLowerCase() !== deployer.address.toLowerCase()) {
      console.log("")
      console.log("❌ FAIL: Current caller is not the submitter!")
      console.log("   Solution: Wait for precedence period to pass OR use submitter's account")
      console.log("")
      console.log("To approve as submitter:")
      console.log(`   1. Use account: ${submitterOperator}`)
      console.log(`   2. Or wait ${400 - blocksSinceSubmission} more blocks`)
    } else {
      console.log("✅ Current caller IS the submitter - can approve")
    }
  } else {
    console.log("✅ Precedence period has passed - anyone can approve")
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
