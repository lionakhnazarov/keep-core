import { ethers } from "hardhat"
import hre from "hardhat"
import { execSync } from "child_process"

/**
 * Get trace using cast call --trace
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
  
  // Build transaction
  const tx = await wrConnected.populateTransaction.approveDkgResult(result)
  
  console.log("==========================================")
  console.log("Tracing Transaction with cast call")
  console.log("==========================================")
  console.log("")
  
  const rpcUrl = process.env.ETHEREUM_RPC_URL || "http://localhost:8545"
  
  try {
    // Use cast call with trace
    const castCommand = `cast call ${tx.to} "${tx.data}" --rpc-url ${rpcUrl} --trace`
    console.log("Running:", castCommand)
    console.log("")
    
    const output = execSync(castCommand, { 
      encoding: 'utf-8',
      maxBuffer: 10 * 1024 * 1024,
      stdio: 'pipe'
    })
    
    // Look for revert information
    const lines = output.split('\n')
    const revertLines = lines.filter(l => 
      l.includes('REVERT') || 
      l.includes('revert') || 
      l.includes('Error') ||
      l.includes('0x') ||
      l.toLowerCase().includes('fail')
    )
    
    if (revertLines.length > 0) {
      console.log("Relevant trace lines:")
      console.log(revertLines.slice(-100).join('\n'))
    } else {
      console.log("Full output:")
      console.log(output.slice(-2000))
    }
    
  } catch (error: any) {
    // cast call returns non-zero on revert, so check stdout
    if (error.stdout) {
      const stdout = error.stdout.toString()
      console.log("Trace output:")
      
      // Look for the revert location
      const lines = stdout.split('\n')
      let foundRevert = false
      const relevantLines: string[] = []
      
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i]
        if (line.includes('REVERT') || line.includes('revert') || line.includes('Error')) {
          foundRevert = true
          // Include context around revert
          const start = Math.max(0, i - 10)
          const end = Math.min(lines.length, i + 20)
          relevantLines.push(...lines.slice(start, end))
          break
        }
      }
      
      if (relevantLines.length > 0) {
        console.log("Revert location found:")
        console.log(relevantLines.join('\n'))
      } else {
        console.log(stdout.slice(-3000))
      }
    }
    
    if (error.stderr) {
      console.log("\nError:")
      console.log(error.stderr.toString().slice(-500))
    }
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
