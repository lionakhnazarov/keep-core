import { ethers } from "hardhat"
import hre from "hardhat"

async function main() {
  console.log("==========================================")
  console.log("Force Approve DKG Result")
  console.log("==========================================")
  console.log("")

  const WalletRegistry = await hre.deployments.get("WalletRegistry")
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address)

  // Get current state
  const state = await wr.getWalletCreationState()
  console.log(`Current DKG State: ${state} (3 = CHALLENGE)`)
  console.log("")

  if (state !== 3) {
    console.error("Error: DKG is not in CHALLENGE state")
    process.exit(1)
  }

  // Get current block
  const currentBlock = await ethers.provider.getBlockNumber()
  console.log(`Current Block: ${currentBlock}`)
  console.log("")

  // Get DKG parameters
  const params = await wr.dkgParameters()
  console.log(`Challenge Period: ${params.resultChallengePeriodLength.toString()} blocks`)
  console.log(`Precedence Period: ${params.submitterPrecedencePeriodLength.toString()} blocks`)
  console.log("")

  // Try to get submitted result from events
  console.log("Searching for DKG result submission event...")
  const filter = wr.filters.DkgResultSubmitted()
  const fromBlock = Math.max(0, currentBlock - 5000) // Search last 5000 blocks
  const events = await wr.queryFilter(filter, fromBlock, currentBlock)
  
  if (events.length === 0) {
    console.error("Error: Could not find DKG result submission event")
    console.error("")
    console.error("The DKG result may have been submitted in an earlier block.")
    console.error("Try extracting the DKG result JSON from node logs:")
    console.error("  grep -i 'submitted.*dkg.*result' logs/node*.log")
    process.exit(1)
  }

  const latestEvent = events[events.length - 1]
  console.log(`Found DKG result submission at block ${latestEvent.blockNumber}`)
  console.log(`Result Hash: ${latestEvent.args.resultHash}`)
  console.log(`Seed: ${latestEvent.args.seed.toString()}`)
  console.log("")

  // Get the result from the event
  const eventResult = latestEvent.args.result
  console.log("DKG Result from event:")
  console.log(`  Submitter Member Index: ${eventResult.submitterMemberIndex}`)
  console.log(`  Group Public Key: ${eventResult.groupPubKey}`)
  console.log(`  Members Hash: ${eventResult.membersHash}`)
  console.log(`  Misbehaved Members: ${eventResult.misbehavedMembersIndices.length}`)
  console.log(`  Signatures Length: ${eventResult.signatures.length}`)
  console.log(`  Signing Members: ${eventResult.signingMembersIndices.length}`)
  console.log(`  Members: ${eventResult.members.length}`)
  console.log("")

  // Calculate challenge period end
  const submissionBlock = latestEvent.blockNumber
  const challengeEnd = submissionBlock + Number(params.resultChallengePeriodLength)
  const precedenceEnd = challengeEnd + Number(params.submitterPrecedencePeriodLength)

  console.log(`Submission Block: ${submissionBlock}`)
  console.log(`Challenge period ends at block: ${challengeEnd}`)
  console.log(`Precedence period ends at block: ${precedenceEnd}`)
  console.log("")

  if (currentBlock < challengeEnd) {
    const blocksNeeded = challengeEnd - currentBlock
    console.error(`Error: Challenge period has not ended yet`)
    console.error(`Need ${blocksNeeded} more blocks`)
    console.error("")
    console.error("Mine blocks: ./scripts/mine-blocks-fast.sh", blocksNeeded)
    process.exit(1)
  }

  console.log("✓ Challenge period has ended")
  console.log("")

  // Try to approve
  console.log("Attempting to approve DKG result...")
  console.log("")
  
  try {
    // Get signer (use deployer or first account)
    const [deployer] = await ethers.getSigners()
    console.log(`Using account: ${deployer.address}`)
    console.log("")

    const wrConnected = wr.connect(deployer)
    
    // Try to approve
    console.log("Sending approval transaction...")
    const tx = await wrConnected.approveDkgResult(eventResult)
    console.log(`Transaction hash: ${tx.hash}`)
    console.log("Waiting for confirmation...")
    
    const receipt = await tx.wait()
    console.log(`✓ Transaction confirmed in block ${receipt.blockNumber}`)
    console.log("")

    // Verify state changed
    const newState = await wr.getWalletCreationState()
    console.log(`New DKG State: ${newState} (0 = IDLE)`)
    console.log("")

    if (newState === 0) {
      console.log("==========================================")
      console.log("✅ SUCCESS! DKG result approved!")
      console.log("==========================================")
      console.log("")
      console.log("Wallet should now be created.")
      console.log("You can request a new wallet: ./scripts/request-new-wallet.sh")
    } else {
      console.log("⚠️  Warning: DKG state is still not IDLE")
      console.log("Check the transaction receipt for events")
    }

  } catch (error: any) {
    console.error("Error approving DKG result:")
    console.error(`  ${error.message}`)
    console.error("")
    
    if (error.data) {
      console.error("Error data:", error.data)
    }
    
    if (error.reason) {
      console.error("Revert reason:", error.reason)
    }
    
    process.exit(1)
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

