import { ethers } from "hardhat"
import hre from "hardhat"

async function main() {
  const { deployments } = hre
  
  const WalletRegistry = await deployments.get("WalletRegistry")
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address)
  
  console.log("==========================================")
  console.log("DKG Status Check")
  console.log("==========================================")
  console.log(`WalletRegistry: ${WalletRegistry.address}`)
  console.log("")
  
  // Method 1: Check wallet creation state
  try {
    const state = await wr.getWalletCreationState()
    const stateNames = ["IDLE", "AWAITING_SEED", "AWAITING_RESULT", "CHALLENGE"]
    console.log(`1. Wallet Creation State: ${stateNames[state]} (${state})`)
  } catch (error: any) {
    console.log(`1. Wallet Creation State: Error - ${error.message}`)
  }
  
  // Method 2: Check if sortition pool is locked
  try {
    const sortitionPool = await wr.sortitionPool()
    const sp = await ethers.getContractAt(
      ["function isLocked() view returns (bool)"],
      sortitionPool
    )
    const isLocked = await sp.isLocked()
    console.log(`2. Sortition Pool Locked: ${isLocked}`)
  } catch (error: any) {
    console.log(`2. Sortition Pool Locked: Error - ${error.message}`)
  }
  
  // Method 3: Check for DKG events
  console.log("")
  console.log("3. Recent DKG Events:")
  try {
    const filterDkgStarted = wr.filters.DkgStarted()
    const filterDkgStateLocked = wr.filters.DkgStateLocked()
    const filterDkgResultSubmitted = wr.filters.DkgResultSubmitted()
    const filterDkgResultApproved = wr.filters.DkgResultApproved()
    
    const [started, locked, submitted, approved] = await Promise.all([
      wr.queryFilter(filterDkgStarted, -1000), // Last 1000 blocks
      wr.queryFilter(filterDkgStateLocked, -1000),
      wr.queryFilter(filterDkgResultSubmitted, -1000),
      wr.queryFilter(filterDkgResultApproved, -1000),
    ])
    
    console.log(`   - DkgStarted events: ${started.length}`)
    if (started.length > 0) {
      started.slice(-3).forEach((event, i) => {
        console.log(`     [${i + 1}] Block ${event.blockNumber}, Seed: ${event.args.seed}`)
      })
    }
    
    console.log(`   - DkgStateLocked events: ${locked.length}`)
    if (locked.length > 0) {
      locked.slice(-3).forEach((event, i) => {
        console.log(`     [${i + 1}] Block ${event.blockNumber}`)
      })
    }
    
    console.log(`   - DkgResultSubmitted events: ${submitted.length}`)
    if (submitted.length > 0) {
      submitted.slice(-3).forEach((event, i) => {
        console.log(`     [${i + 1}] Block ${event.blockNumber}, ResultHash: ${event.args.resultHash}`)
      })
    }
    
    console.log(`   - DkgResultApproved events: ${approved.length}`)
    if (approved.length > 0) {
      approved.slice(-3).forEach((event, i) => {
        console.log(`     [${i + 1}] Block ${event.blockNumber}, ResultHash: ${event.args.resultHash}`)
      })
    }
  } catch (error: any) {
    console.log(`   Error querying events: ${error.message}`)
  }
  
  // Method 4: Check DKG timeout status
  try {
    const hasTimedOut = await wr.hasDkgTimedOut()
    console.log("")
    console.log(`4. DKG Timed Out: ${hasTimedOut}`)
  } catch (error: any) {
    console.log(`4. DKG Timed Out: Error - ${error.message}`)
  }
  
  // Method 5: Check DKG parameters
  try {
    const params = await wr.dkgParameters()
    console.log("")
    console.log("5. DKG Parameters:")
    console.log(`   - Result Challenge Period Length: ${params.resultChallengePeriodLength} blocks`)
    console.log(`   - Result Submission Timeout: ${params.resultSubmissionTimeout} blocks`)
    console.log(`   - Seed Timeout: ${params.seedTimeout} blocks`)
  } catch (error: any) {
    console.log(`5. DKG Parameters: Error - ${error.message}`)
  }
  
  console.log("")
  console.log("==========================================")
}

main().catch(console.error)
