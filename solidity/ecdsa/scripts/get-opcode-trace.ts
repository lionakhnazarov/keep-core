import { ethers } from "hardhat"
import hre from "hardhat"
import { execSync } from "child_process"

/**
 * Get opcode-level trace using cast run --trace
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
  console.log("Getting Opcode-Level Trace")
  console.log("==========================================")
  console.log("")
  console.log(`WalletRegistry: ${WalletRegistry.address}`)
  console.log(`From: ${deployer.address}`)
  console.log(`To: ${tx.to}`)
  console.log("")
  
  // Get RPC URL from hardhat config
  const network = hre.network.config as any
  const rpcUrl = network.url || process.env.ETHEREUM_RPC_URL || "http://localhost:8545"
  
  console.log(`RPC URL: ${rpcUrl}`)
  console.log("")
  console.log("Running cast run --trace...")
  console.log("(This may take a moment)")
  console.log("")
  
  try {
    // Use cast run --trace to get detailed trace
    // Format: cast run <to> <data> --rpc-url <url> --trace
    const castCommand = `cast run ${tx.to} ${tx.data} --rpc-url ${rpcUrl} --trace`
    console.log(`Command: ${castCommand}`)
    console.log("")
    
    const output = execSync(castCommand, { 
      encoding: 'utf-8',
      maxBuffer: 10 * 1024 * 1024, // 10MB buffer
      stdio: 'pipe'
    })
    
    // Parse and show relevant parts
    const lines = output.split('\n')
    let inTrace = false
    let traceLines: string[] = []
    
    for (const line of lines) {
      if (line.includes('Trace') || line.includes('REVERT') || line.includes('Error')) {
        inTrace = true
      }
      if (inTrace) {
        traceLines.push(line)
        if (traceLines.length > 200) break // Limit output
      }
    }
    
    if (traceLines.length > 0) {
      console.log("Trace output (last 200 lines):")
      console.log(traceLines.join('\n'))
    } else {
      console.log("Full output:")
      console.log(output.slice(-5000)) // Last 5000 chars
    }
    
  } catch (error: any) {
    console.log("Cast trace output:")
    if (error.stdout) {
      const stdout = error.stdout.toString()
      // Look for revert information
      if (stdout.includes('REVERT') || stdout.includes('revert')) {
        console.log("Found REVERT in output:")
        const lines = stdout.split('\n')
        const relevantLines = lines.filter(l => 
          l.includes('REVERT') || 
          l.includes('revert') || 
          l.includes('Error') ||
          l.includes('0x') ||
          l.includes('pc=')
        )
        console.log(relevantLines.slice(-50).join('\n'))
      } else {
        console.log(stdout.slice(-3000))
      }
    }
    if (error.stderr) {
      console.log("\nError output:")
      console.log(error.stderr.toString().slice(-1000))
    }
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
