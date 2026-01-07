import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * This script extracts the exact DKG result from the submission event
 * and approves it directly. This bypasses the hash mismatch issue
 * by using the exact same data structure that was submitted.
 */
async function main() {
  console.log("==========================================")
  console.log("Approve DKG Result from Event Data")
  console.log("==========================================")
  console.log("")
  console.log("This script extracts the exact DKG result from the")
  console.log("submission event and approves it, bypassing hash mismatch issues.")
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

  // Get DKG result submission event
  console.log("Searching for DKG result submission event...")
  const filter = wr.filters.DkgResultSubmitted()
  const currentBlock = await ethers.provider.getBlockNumber()
  const fromBlock = Math.max(0, currentBlock - 5000)
  const events = await wr.queryFilter(filter, fromBlock, currentBlock)
  
  if (events.length === 0) {
    console.error("Error: Could not find DKG result submission event")
    process.exit(1)
  }

  const latestEvent = events[events.length - 1]
  console.log(`Found DKG result submission at block ${latestEvent.blockNumber}`)
  console.log(`Event Result Hash: ${latestEvent.args.resultHash}`)
  console.log("")

  // Get the result from the event - this is the EXACT structure that was submitted
  const eventResult = latestEvent.args.result
  
  // Get current block and check timing
  const submissionBlock = latestEvent.blockNumber
  const params = await wr.dkgParameters()
  const challengeEnd = submissionBlock + Number(params.resultChallengePeriodLength)
  const precedenceEnd = challengeEnd + Number(params.submitterPrecedencePeriodLength)

  console.log(`Submission Block: ${submissionBlock}`)
  console.log(`Current Block: ${currentBlock}`)
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

  // Check if we're past precedence period
  const submitterIndex = eventResult.submitterMemberIndex
  const [deployer] = await ethers.getSigners()
  const deployerAddress = deployer.address
  
  // Get submitter address from sortition pool
  // Note: This might fail if we can't access the sortition pool
  let canApprove = true
  if (currentBlock < precedenceEnd) {
    // Check if deployer is the submitter
    // We can't easily check this, so we'll try and let it fail if needed
    console.log("⚠️  Still in precedence period")
    console.log(`   Only submitter (member index ${submitterIndex}) can approve now`)
    console.log(`   After block ${precedenceEnd}, anyone can approve`)
    console.log("")
    console.log("Attempting approval anyway...")
    console.log("")
  }

  // Use the exact result from the event
  console.log("Using exact result structure from submission event...")
  console.log("")
  console.log("Result details:")
  console.log(`  Submitter Member Index: ${eventResult.submitterMemberIndex.toString()}`)
  console.log(`  Group Public Key: ${eventResult.groupPubKey}`)
  console.log(`  Members Hash: ${eventResult.membersHash}`)
  console.log(`  Misbehaved Members: ${eventResult.misbehavedMembersIndices.length}`)
  console.log(`  Signatures Length: ${eventResult.signatures.length} bytes`)
  console.log(`  Signing Members: ${eventResult.signingMembersIndices.length}`)
  console.log(`  Members: ${eventResult.members.length}`)
  console.log("")

  try {
    const wrConnected = wr.connect(deployer)
    
    console.log(`Using account: ${deployerAddress}`)
    console.log("")
    console.log("Sending approval transaction...")
    
    // Approve using the exact result from the event
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
      console.log("The wallet should now be created.")
      console.log("You can check wallet creation:")
      console.log("  ./scripts/check-wallet-creation.sh")
      console.log("")
      console.log("Or request a new wallet:")
      console.log("  cd solidity/ecdsa && npx hardhat run scripts/request-new-wallet.ts --network development")
    } else {
      console.log("⚠️  Warning: DKG state is still not IDLE")
      console.log("Check the transaction receipt for events")
    }

  } catch (error: any) {
    console.error("Error approving DKG result:")
    console.error(`  ${error.message}`)
    console.error("")
    
    if (error.reason) {
      console.error(`Revert reason: ${error.reason}`)
    }
    
    if (error.data) {
      console.error("Error data:", error.data)
    }
    
    // Common error reasons
    if (error.message.includes("precedence")) {
      console.error("")
      console.error("⚠️  Still in precedence period - only submitter can approve")
      console.error(`   Wait until block ${precedenceEnd} for anyone to approve`)
      console.error(`   Current block: ${currentBlock}`)
      console.error(`   Blocks remaining: ${precedenceEnd - currentBlock}`)
    }
    
    if (error.message.includes("hash") || error.message.includes("different")) {
      console.error("")
      console.error("⚠️  Hash mismatch detected")
      console.error("   This shouldn't happen when using event data directly")
      console.error("   The event data might be decoded incorrectly")
    }
    
    process.exit(1)
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

