import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * Capture the exact revert reason for DKG approval failure
 * This script extracts the DKG result from the event and attempts approval
 * to capture the exact revert reason with full error details.
 */
async function main() {
  const WalletRegistry = await hre.deployments.get("WalletRegistry")
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address)

  console.log("==========================================")
  console.log("Capturing DKG Approval Revert Reason")
  console.log("==========================================")
  console.log(`WalletRegistry: ${WalletRegistry.address}`)
  console.log(`Network: ${hre.network.name}`)
  console.log("")

  // Get DKG result from the most recent submission event
  console.log("Step 1: Finding DKG result submission event...")
  const filter = wr.filters.DkgResultSubmitted()
  
  // Search from a reasonable block range (last 2000 blocks)
  const currentBlock = await ethers.provider.getBlockNumber()
  const fromBlock = Math.max(0, currentBlock - 2000)
  
  const events = await wr.queryFilter(filter, fromBlock)
  if (events.length === 0) {
    console.error("❌ No DkgResultSubmitted events found")
    console.error(`   Searched from block ${fromBlock} to ${currentBlock}`)
    process.exit(1)
  }

  const latestEvent = events[events.length - 1]
  const result = latestEvent.args.result
  const resultHash = latestEvent.args.resultHash
  const seed = latestEvent.args.seed
  
  console.log(`✓ Found event at block ${latestEvent.blockNumber}`)
  console.log(`  Result Hash: ${resultHash}`)
  console.log(`  Seed: ${seed}`)
  console.log(`  Submitter Member Index: ${result.submitterMemberIndex}`)
  console.log(`  Group Public Key: 0x${result.groupPubKey.slice(2, 18)}...`)
  console.log(`  Misbehaved Members: ${result.misbehavedMembersIndices.length}`)
  console.log(`  Signing Members: ${result.signingMembersIndices.length}`)
  console.log(`  Total Members: ${result.members.length}`)
  console.log("")

  // Get current state
  console.log("Step 2: Checking contract state...")
  const state = await wr.getWalletCreationState()
  const stateNames = ["IDLE", "AWAITING_SEED", "AWAITING_RESULT", "CHALLENGE"]
  console.log(`  Current State: ${state} (${stateNames[state]})`)
  
  if (state !== 3) {
    console.error(`❌ State is not CHALLENGE (expected 3, got ${state})`)
    console.error("   Approval can only happen in CHALLENGE state")
    process.exit(1)
  }
  console.log("✓ State is CHALLENGE (correct)")
  console.log("")

  // Get DKG parameters
  console.log("Step 3: Checking DKG parameters...")
  const params = await wr.dkgParameters()
  console.log(`  Challenge Period: ${params.resultChallengePeriodLength} blocks`)
  console.log(`  Precedence Period: ${params.submitterPrecedencePeriodLength} blocks`)
  console.log("")

  // Check timing
  console.log("Step 4: Checking timing requirements...")
  const currentBlockNum = await ethers.provider.getBlockNumber()
  
  try {
    // Note: submittedResultBlock() may not be available in the ABI, so we use the event block
    const submittedBlock = latestEvent.blockNumber
    console.log(`  Submitted Block: ${submittedBlock}`)
    console.log(`  Current Block: ${currentBlockNum}`)
    
    const challengeEnd = submittedBlock + params.resultChallengePeriodLength.toNumber()
    const precedenceEnd = challengeEnd + params.submitterPrecedencePeriodLength.toNumber()
    
    console.log(`  Challenge Period End: ${challengeEnd}`)
    console.log(`  Precedence Period End: ${precedenceEnd}`)
    
    if (currentBlockNum < challengeEnd) {
      console.error(`❌ Current block (${currentBlockNum}) is before challenge period end (${challengeEnd})`)
      process.exit(1)
    }
    
    const submitterIndex = result.submitterMemberIndex.toNumber()
    if (currentBlockNum < precedenceEnd && submitterIndex !== 1) {
      console.warn(`⚠️  Current block (${currentBlockNum}) is in precedence period (ends at ${precedenceEnd})`)
      console.warn(`   Only submitter (member ${submitterIndex}) can approve now`)
    }
    
    console.log("✓ Timing requirements met")
  } catch (error: any) {
    console.error(`❌ Error checking timing: ${error.message}`)
  }
  console.log("")

  // Get signer
  const [deployer] = await ethers.getSigners()
  const wrConnected = wr.connect(deployer)
  console.log(`Step 5: Using signer: ${deployer.address}`)
  console.log("")

  // Verify hash match
  console.log("Step 6: Verifying result hash...")
  try {
    const calculatedHash = ethers.utils.keccak256(
      ethers.utils.defaultAbiCoder.encode(
        [
          "tuple(uint256 submitterMemberIndex, bytes groupPubKey, uint8[] misbehavedMembersIndices, bytes signatures, uint256[] signingMembersIndices, uint32[] members, bytes32 membersHash)",
        ],
        [result]
      )
    )
    
    console.log(`  Calculated Hash: ${calculatedHash}`)
    console.log(`  Event Hash:      ${resultHash}`)
    
    if (calculatedHash.toLowerCase() !== resultHash.toLowerCase()) {
      console.error("❌ Hash mismatch!")
      console.error("   This is likely the cause of the revert")
      console.error("   The result structure doesn't match what was submitted")
    } else {
      console.log("✓ Hash matches")
    }
  } catch (hashError: any) {
    console.warn(`⚠️  Could not verify hash: ${hashError.message}`)
  }
  console.log("")

  // Attempt approval with detailed error capture
  console.log("Step 7: Attempting approval call to capture revert reason...")
  console.log("")

  try {
    // Use callStatic to get the revert reason without sending a transaction
    await wrConnected.callStatic.approveDkgResult(result)
    console.log("✅ Approval would succeed!")
    console.log("   (No revert reason - call would work)")
  } catch (error: any) {
    console.log("❌ Approval call failed:")
    console.log("")
    
    // Extract error message
    if (error.message) {
      console.log(`Error Message: ${error.message}`)
    }
    
    // Extract reason if available
    if (error.reason) {
      console.log(`Reason: ${error.reason}`)
    }
    
    // Decode error data
    if (error.data) {
      console.log(`Error Data: ${error.data}`)
      console.log("")
      
      // Try to match known error signatures
      const errorSignatures: { [key: string]: string } = {
        "Current state is not CHALLENGE": ethers.utils.id("Current state is not CHALLENGE").slice(0, 10),
        "Challenge period has not passed yet": ethers.utils.id("Challenge period has not passed yet").slice(0, 10),
        "Result under approval is different than the submitted one": ethers.utils.id("Result under approval is different than the submitted one").slice(0, 10),
        "Only the DKG result submitter can approve the result at this moment": ethers.utils.id("Only the DKG result submitter can approve the result at this moment").slice(0, 10),
      }
      
      console.log("Matching error signatures:")
      let matched = false
      for (const [errorMsg, sig] of Object.entries(errorSignatures)) {
        if (error.data.startsWith(sig)) {
          console.log("")
          console.log(`🔍 MATCHED ERROR: ${errorMsg}`)
          console.log(`   Signature: ${sig}`)
          matched = true
          break
        }
      }
      
      if (!matched) {
        console.log("⚠️  No known error signature matched")
        console.log(`   First 10 bytes: ${error.data.slice(0, 10)}`)
        console.log("")
        console.log("Possible causes:")
        console.log("  1. Custom error (not a require statement)")
        console.log("  2. Error in nested contract call")
        console.log("  3. Gas estimation failure")
      }
    }
    
    // Try to get more details using provider.call
    console.log("")
    console.log("Step 8: Attempting provider.call for additional details...")
    try {
      const tx = await wrConnected.populateTransaction.approveDkgResult(result)
      const result2 = await ethers.provider.call(tx)
      console.log(`Raw result: ${result2}`)
    } catch (e2: any) {
      console.log(`Provider call error: ${e2.message}`)
      if (e2.data) {
        console.log(`Error data: ${e2.data}`)
      }
    }
    
    // Try debug trace if available
    if (hre.network.name === "hardhat" || hre.network.name === "development") {
      console.log("")
      console.log("Step 9: Attempting debug trace...")
      try {
        const tx = await wrConnected.populateTransaction.approveDkgResult(result)
        const traceResult = await hre.network.provider.send("debug_traceCall", [
          {
            from: deployer.address,
            to: tx.to,
            data: tx.data,
            gas: "0x7a1200", // 8M gas
          },
          "latest",
          {
            tracer: "callTracer",
            tracerConfig: {
              onlyTopCall: false,
              withLog: true,
            },
          },
        ])
        
        if (traceResult.error) {
          console.log(`Trace Error: ${traceResult.error}`)
        }
        
        // Find the revert point
        function findRevert(call: any): any {
          if (call.error) {
            return call
          }
          if (call.calls) {
            for (const subCall of call.calls) {
              const revert = findRevert(subCall)
              if (revert) return revert
            }
          }
          return null
        }
        
        const revertCall = findRevert(traceResult)
        if (revertCall) {
          console.log("")
          console.log("📍 Revert point found:")
          console.log(`   Type: ${revertCall.type}`)
          console.log(`   To: ${revertCall.to}`)
          console.log(`   Error: ${revertCall.error}`)
        }
      } catch (traceError: any) {
        console.log(`Trace not available: ${traceError.message}`)
      }
    }
  }
  
  console.log("")
  console.log("==========================================")
  console.log("Investigation Complete")
  console.log("==========================================")
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

