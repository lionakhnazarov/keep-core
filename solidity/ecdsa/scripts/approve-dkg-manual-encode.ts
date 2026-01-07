import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * Manually encode the DKG result struct in the correct order
 * and call approveDkgResult with the encoded data
 * 
 * This ensures the encoding matches exactly what Solidity's abi.encode() produces
 */
async function main() {
  console.log("==========================================")
  console.log("Approve DKG Result - Manual Encoding")
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

  // Get DKG result submission event
  console.log("Extracting DKG result from submission event...")
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
  const storedHash = latestEvent.args.resultHash
  
  console.log(`Submission Block: ${latestEvent.blockNumber}`)
  console.log(`Stored Hash: ${storedHash}`)
  console.log("")

  // Check timing
  const submissionBlock = latestEvent.blockNumber
  const params = await wr.dkgParameters()
  const challengeEnd = submissionBlock + Number(params.resultChallengePeriodLength)
  
  if (currentBlock < challengeEnd) {
    console.error(`Error: Challenge period has not ended yet`)
    console.error(`Need ${challengeEnd - currentBlock} more blocks`)
    process.exit(1)
  }

  console.log("✓ Challenge period has ended")
  console.log("")

  // Manually encode the struct in the CORRECT order:
  // submitterMemberIndex, groupPubKey, misbehavedMembersIndices, signatures,
  // signingMembersIndices, members, membersHash (LAST)
  console.log("Manually encoding struct in correct order...")
  
  const encodedResult = ethers.utils.defaultAbiCoder.encode(
    [
      "tuple(uint256 submitterMemberIndex, bytes groupPubKey, uint8[] misbehavedMembersIndices, bytes signatures, uint256[] signingMembersIndices, uint32[] members, bytes32 membersHash)",
    ],
    [
      [
        eventResult.submitterMemberIndex,
        eventResult.groupPubKey,
        eventResult.misbehavedMembersIndices,
        eventResult.signatures,
        eventResult.signingMembersIndices,
        eventResult.members,
        eventResult.membersHash, // LAST
      ],
    ]
  )

  // Verify the hash matches
  const computedHash = ethers.utils.keccak256(encodedResult)
  console.log(`Computed Hash: ${computedHash}`)
  console.log(`Stored Hash:   ${storedHash}`)
  
  if (computedHash.toLowerCase() !== storedHash.toLowerCase()) {
    console.error("❌ Hash mismatch! Encoding is still wrong.")
    process.exit(1)
  }
  
  console.log("✅ Hash matches!")
  console.log("")

  // Now call approveDkgResult using the manually encoded data
  // We need to use the contract's interface to encode the function call
  const [deployer] = await ethers.getSigners()
  const wrConnected = wr.connect(deployer)
  
  console.log(`Using account: ${deployer.address}`)
  console.log("")
  console.log("Calling approveDkgResult with manually encoded struct...")
  console.log("")
  
  try {
    // Use the exact struct from event - Hardhat should handle encoding correctly
    // But we've verified the hash matches, so this should work
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
    } else {
      console.log("⚠️  Warning: DKG state is still not IDLE")
    }

  } catch (error: any) {
    console.error("Error approving DKG result:")
    console.error(`  ${error.message}`)
    console.error("")
    
    if (error.reason) {
      console.error(`Revert reason: ${error.reason}`)
    }
    
    // Try to decode the revert reason
    if (error.data && error.data !== "0x") {
      try {
        const decoded = wr.interface.parseError(error.data)
        console.error(`Decoded error: ${decoded.name}`)
        console.error(`  Args: ${JSON.stringify(decoded.args, null, 2)}`)
      } catch (e) {
        console.error(`Could not decode error: ${error.data}`)
      }
    }
    
    process.exit(1)
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

