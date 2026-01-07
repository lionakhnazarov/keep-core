import { ethers } from "hardhat"
import hre from "hardhat"

async function main() {
  console.log("==========================================")
  console.log("Approve DKG Result (Direct)")
  console.log("==========================================")
  console.log("")

  const WalletRegistry = await hre.deployments.get("WalletRegistry")
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address)

  // Get current state
  const state = await wr.getWalletCreationState()
  console.log(`Current DKG State: ${state}`)
  console.log("  0 = IDLE")
  console.log("  1 = AWAITING_SEED")
  console.log("  2 = AWAITING_RESULT")
  console.log("  3 = CHALLENGE")
  console.log("")

  if (state !== 3) {
    console.error("Error: DKG is not in CHALLENGE state (state =", state, ")")
    process.exit(1)
  }

  // Get submitted result hash
  const submittedHash = await wr.submittedResultHash()
  console.log(`Submitted Result Hash: ${submittedHash}`)
  console.log("")

  // Get submission block
  const submissionBlock = await wr.submittedResultBlock()
  console.log(`Submission Block: ${submissionBlock.toString()}`)
  console.log("")

  // Get current block
  const currentBlock = await ethers.provider.getBlockNumber()
  console.log(`Current Block: ${currentBlock}`)
  console.log("")

  // Get DKG parameters
  const params = await wr.dkgParameters()
  const challengePeriod = params.resultChallengePeriodLength
  const precedencePeriod = params.submitterPrecedencePeriodLength

  console.log(`Challenge Period: ${challengePeriod.toString()} blocks`)
  console.log(`Precedence Period: ${precedencePeriod.toString()} blocks`)
  console.log("")

  const challengeEnd = submissionBlock.add(challengePeriod)
  const precedenceEnd = challengeEnd.add(precedencePeriod)

  console.log(`Challenge period ends at block: ${challengeEnd.toString()}`)
  console.log(`Precedence period ends at block: ${precedenceEnd.toString()}`)
  console.log("")

  if (currentBlock < challengeEnd) {
    const blocksNeeded = challengeEnd.sub(currentBlock)
    console.error(`Error: Challenge period has not ended yet`)
    console.error(`Need ${blocksNeeded.toString()} more blocks`)
    console.error("")
    console.error("Mine blocks: ./scripts/mine-blocks-fast.sh", blocksNeeded.toString())
    process.exit(1)
  }

  console.log("✓ Challenge period has ended")
  console.log("")

  // Try to get the DKG result from events
  console.log("Attempting to find DKG result from events...")
  const filter = wr.filters.DkgResultSubmitted()
  const events = await wr.queryFilter(filter, submissionBlock.toNumber(), currentBlock)
  
  if (events.length === 0) {
    console.error("Error: Could not find DKG result submission event")
    console.error("")
    console.error("You may need to:")
    console.error("  1. Extract DKG result JSON from node logs")
    console.error("  2. Use that JSON to approve manually")
    console.error("")
    console.error("Check logs: grep -i 'submitted.*dkg.*result' logs/node*.log")
    process.exit(1)
  }

  const latestEvent = events[events.length - 1]
  console.log(`Found DKG result submission event at block ${latestEvent.blockNumber}`)
  console.log("")

  // The event contains the result, but we need to reconstruct it
  // For now, let's try to approve using the event data
  console.log("⚠️  Note: This script needs the exact DKG result JSON to approve")
  console.log("")
  console.log("The approval requires the exact result structure that was submitted.")
  console.log("")
  console.log("To get the DKG result JSON:")
  console.log("  1. Check node logs: grep -i 'submitted.*dkg.*result' logs/node*.log")
  console.log("  2. Extract the JSON from the log entry")
  console.log("  3. Use it with: ./scripts/approve-dkg-result.sh")
  console.log("")
  console.log("Or use the existing approve script if it has the correct JSON:")
  console.log("  ./scripts/approve")
  console.log("")

  // Check if we can at least verify the hash matches
  console.log("To manually approve, you need:")
  console.log("  - The exact DKG result JSON that matches hash:", submittedHash)
  console.log("  - Call: WalletRegistry.approveDkgResult(dkgResult)")
  console.log("")
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
