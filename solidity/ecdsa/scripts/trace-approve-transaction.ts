import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * Trace approveDkgResult transaction to find exact revert point
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
  
  const [deployer] = await ethers.getSigners()
  const wrConnected = wr.connect(deployer)
  
  console.log("==========================================")
  console.log("Tracing approveDkgResult Transaction")
  console.log("==========================================")
  console.log("")
  console.log(`WalletRegistry: ${WalletRegistry.address}`)
  console.log(`Caller: ${deployer.address}`)
  console.log("")
  
  // Check hash match first
  console.log("Step 1: Checking hash match...")
  try {
    // Get submitted hash from contract (need to check how to access this)
    // For now, let's calculate and compare
    const calculatedHash = ethers.utils.keccak256(
      ethers.utils.defaultAbiCoder.encode(
        [
          "tuple(uint256 submitterMemberIndex, bytes groupPubKey, uint8[] misbehavedMembersIndices, bytes signatures, uint256[] signingMembersIndices, uint32[] members, bytes32 membersHash)",
        ],
        [result]
      )
    )
    
    console.log(`Calculated hash: ${calculatedHash}`)
    console.log("")
  } catch (e: any) {
    console.log(`Hash calculation error: ${e.message}`)
  }
  
  // Build the transaction
  const tx = await wrConnected.populateTransaction.approveDkgResult(result)
  
  console.log("Step 2: Attempting transaction call...")
  console.log("")
  
  // Try to trace using Hardhat's trace
  try {
    // Use callStatic with verbose error handling
    try {
      await wrConnected.callStatic.approveDkgResult(result)
      console.log("✅ Transaction would succeed!")
    } catch (error: any) {
      console.log("❌ Transaction would fail:")
      console.log(`   ${error.message}`)
      
      // Try to get trace if available
      if (hre.network.name === "hardhat" || hre.network.name === "development") {
        console.log("")
        console.log("Step 3: Attempting detailed trace...")
        
        try {
          const traceResult = await hre.network.provider.send("debug_traceCall", [
            {
              from: deployer.address,
              to: tx.to,
              data: tx.data,
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
          
          console.log("")
          console.log("Trace result (simplified):")
          if (traceResult.error) {
            console.log(`Error: ${traceResult.error}`)
          }
          if (traceResult.calls) {
            console.log(`Number of calls: ${traceResult.calls.length}`)
            // Show last few calls
            const lastCalls = traceResult.calls.slice(-5)
            lastCalls.forEach((call: any, i: number) => {
              console.log(`  Call ${i + 1}: ${call.type} to ${call.to}`)
              if (call.error) {
                console.log(`    ERROR: ${call.error}`)
              }
            })
          }
          
        } catch (traceError: any) {
          console.log(`Trace not available: ${traceError.message}`)
          console.log("")
          console.log("Alternative: Check contract state manually")
        }
      }
    }
  } catch (error: any) {
    console.error("Error during trace:")
    console.error(error)
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
