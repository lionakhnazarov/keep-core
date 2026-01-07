import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * Use debug_traceCall to find the exact revert point in approveDkgResult
 */
async function main() {
  const WalletRegistry = await hre.deployments.get("WalletRegistry")
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address)

  console.log("==========================================")
  console.log("Debug Trace: Finding Exact Revert Point")
  console.log("==========================================")
  console.log(`WalletRegistry: ${WalletRegistry.address}`)
  console.log(`Network: ${hre.network.name}`)
  console.log("")

  // Get DKG result from event
  const filter = wr.filters.DkgResultSubmitted()
  const currentBlock = await ethers.provider.getBlockNumber()
  const fromBlock = Math.max(0, currentBlock - 2000)
  
  const events = await wr.queryFilter(filter, fromBlock)
  if (events.length === 0) {
    console.error("❌ No DkgResultSubmitted events found")
    process.exit(1)
  }

  const latestEvent = events[events.length - 1]
  const result = latestEvent.args.result
  
  console.log(`Found event at block ${latestEvent.blockNumber}`)
  console.log(`Result Hash: ${latestEvent.args.resultHash}`)
  console.log("")

  const [deployer] = await ethers.getSigners()
  const wrConnected = wr.connect(deployer)
  
  // Build transaction
  const tx = await wrConnected.populateTransaction.approveDkgResult(result)
  
  console.log("Attempting debug_traceCall...")
  console.log("")

  try {
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
    
    console.log("Trace Result:")
    console.log(JSON.stringify(traceResult, null, 2))
    console.log("")
    
    // Find revert point
    function findRevert(call: any, depth: number = 0): any {
      const indent = "  ".repeat(depth)
      
      if (call.error) {
        console.log(`${indent}❌ REVERT FOUND at depth ${depth}:`)
        console.log(`${indent}   Type: ${call.type}`)
        console.log(`${indent}   To: ${call.to}`)
        console.log(`${indent}   Error: ${call.error}`)
        if (call.input) {
          console.log(`${indent}   Input: ${call.input.slice(0, 100)}...`)
        }
        return call
      }
      
      if (call.calls && call.calls.length > 0) {
        for (const subCall of call.calls) {
          const revert = findRevert(subCall, depth + 1)
          if (revert) return revert
        }
      }
      
      return null
    }
    
    const revertCall = findRevert(traceResult)
    
    if (!revertCall) {
      console.log("⚠️  No revert found in trace (transaction might succeed?)")
    } else {
      console.log("")
      console.log("==========================================")
      console.log("Revert Analysis")
      console.log("==========================================")
      console.log(`Revert occurred in: ${revertCall.type}`)
      console.log(`Contract: ${revertCall.to}`)
      console.log(`Error: ${revertCall.error}`)
      
      // Try to identify the contract
      if (revertCall.to?.toLowerCase() === WalletRegistry.address.toLowerCase()) {
        console.log("")
        console.log("📍 Revert is in WalletRegistry contract")
        console.log("   This could be:")
        console.log("   - approveResult() in EcdsaDkg library")
        console.log("   - addWallet() in Wallets library")
        console.log("   - WalletOwner callback")
      }
    }
    
  } catch (traceError: any) {
    console.error(`❌ Trace failed: ${traceError.message}`)
    console.error("")
    console.error("This might mean:")
    console.error("  1. debug_traceCall is not available on this network")
    console.error("  2. The transaction data is invalid")
    console.error("  3. Network/RPC issue")
    
    // Fallback: try to get more info from the error
    console.log("")
    console.log("Attempting fallback: callStatic with verbose error...")
    try {
      await wrConnected.callStatic.approveDkgResult(result)
    } catch (error: any) {
      console.log(`Error: ${error.message}`)
      if (error.data) {
        console.log(`Data: ${error.data}`)
      }
    }
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

