import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * Trace the approval transaction to find the exact revert point
 * Uses Hardhat's trace capabilities to see where the transaction fails
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
  console.log("Trace Approval Transaction Revert")
  console.log("==========================================")
  console.log("")
  console.log(`Submission Block: ${latestEvent.blockNumber}`)
  console.log(`Stored Hash: ${latestEvent.args.resultHash}`)
  console.log("")

  const [deployer] = await ethers.getSigners()
  const wrConnected = wr.connect(deployer)
  
  // Encode the function call
  const iface = wr.interface
  const encodedCall = iface.encodeFunctionData("approveDkgResult", [eventResult])
  
  console.log("Calling approveDkgResult with tracing...")
  console.log("")
  
  try {
    // Use callStatic with verbose error handling
    const result = await wrConnected.callStatic.approveDkgResult(eventResult)
    console.log("✅ Static call succeeded!")
    console.log(`Result: ${result}`)
  } catch (error: any) {
    console.log("❌ Static call failed")
    console.log("")
    
    // Try to get more details using debug_traceCall
    console.log("Attempting to trace the call...")
    console.log("")
    
    try {
      // Use Hardhat's network provider to call debug_traceCall
      const traceResult = await hre.network.provider.send("debug_traceCall", [
        {
          from: deployer.address,
          to: WalletRegistry.address,
          data: encodedCall,
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
      
      console.log("Trace result:")
      console.log(JSON.stringify(traceResult, null, 2))
      
      // Look for error or revert in the trace
      if (traceResult.error) {
        console.log("")
        console.log("Error found in trace:")
        console.log(`  Error: ${traceResult.error}`)
      }
      
      // Check for revert reason
      if (traceResult.revertReason) {
        console.log("")
        console.log("Revert reason:")
        console.log(`  ${traceResult.revertReason}`)
      }
      
    } catch (traceError: any) {
      console.log("Could not trace call:")
      console.log(`  ${traceError.message}`)
      console.log("")
      console.log("Trying alternative method...")
      
      // Alternative: Try to decode the error from the error object
      if (error.data && error.data !== "0x") {
        console.log("")
        console.log("Error data:", error.data)
        
        // Try to decode as custom error
        try {
          // Common error signatures
          const errorSignatures = [
            "Result under approval is different than the submitted one",
            "Current state is not CHALLENGE",
            "Challenge period has not passed yet",
            "Only the DKG result submitter can approve the result at this moment",
          ]
          
          for (const errorMsg of errorSignatures) {
            const errorSig = ethers.utils.id(errorMsg).slice(0, 10)
            if (error.data.startsWith(errorSig)) {
              console.log("")
              console.log(`Likely error: ${errorMsg}`)
              break
            }
          }
        } catch (e) {
          // Ignore
        }
      }
      
      // Try to get revert reason using eth_call with verbose output
      try {
        const callResult = await hre.network.provider.send("eth_call", [
          {
            from: deployer.address,
            to: WalletRegistry.address,
            data: encodedCall,
          },
          "latest",
        ])
        console.log("Call succeeded:", callResult)
      } catch (callError: any) {
        console.log("")
        console.log("eth_call error:")
        console.log(`  ${callError.message}`)
        if (callError.data) {
          console.log(`  Data: ${callError.data}`)
        }
      }
    }
    
    // Also try to check the contract state
    console.log("")
    console.log("Checking contract state...")
    console.log("")
    
    const state = await wr.getWalletCreationState()
    console.log(`Current DKG State: ${state}`)
    
    // Check timing
    const submissionBlock = latestEvent.blockNumber
    const params = await wr.dkgParameters()
    const challengeEnd = submissionBlock + Number(params.resultChallengePeriodLength)
    const precedenceEnd = challengeEnd + Number(params.submitterPrecedencePeriodLength)
    
    console.log(`Submission Block: ${submissionBlock}`)
    console.log(`Current Block: ${currentBlock}`)
    console.log(`Challenge period ends: ${challengeEnd}`)
    console.log(`Precedence period ends: ${precedenceEnd}`)
    
    // Verify hash manually
    console.log("")
    console.log("Verifying hash manually...")
    const manualEncoded = ethers.utils.defaultAbiCoder.encode(
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
          eventResult.membersHash,
        ],
      ]
    )
    const manualHash = ethers.utils.keccak256(manualEncoded)
    console.log(`Manual hash: ${manualHash}`)
    console.log(`Stored hash: ${latestEvent.args.resultHash}`)
    console.log(`Match: ${manualHash.toLowerCase() === latestEvent.args.resultHash.toLowerCase() ? "✅ YES" : "❌ NO"}`)
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

