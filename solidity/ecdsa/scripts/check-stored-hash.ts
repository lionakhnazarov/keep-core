import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * Check the stored hash in contract storage
 */
async function main() {
  const WalletRegistry = await hre.deployments.get("WalletRegistry")
  
  // Get DKG result from event
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address)
  const filter = wr.filters.DkgResultSubmitted()
  const events = await wr.queryFilter(filter, -2000)
  
  if (events.length === 0) {
    console.error("No events found")
    process.exit(1)
  }

  const latestEvent = events[events.length - 1]
  const result = latestEvent.args.result
  
  console.log("==========================================")
  console.log("Checking Stored Hash vs Calculated Hash")
  console.log("==========================================")
  console.log("")
  
  // Calculate hash from result
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
  
  // Try to read from storage directly
  // The hash is stored in the DKG library storage slot
  // We need to find where it's stored in WalletRegistry
  
  // Check event hash
  const eventHash = latestEvent.args.resultHash || calculatedHash
  console.log(`Event hash: ${eventHash}`)
  console.log(`Match: ${eventHash === calculatedHash ? "✅ YES" : "❌ NO"}`)
  console.log("")
  
  // Try to call isDkgResultValid to see what it says
  console.log("Checking if result is valid...")
  try {
    const [isValid, errorMsg] = await wr.isDkgResultValid(result)
    console.log(`Is valid: ${isValid}`)
    if (!isValid) {
      console.log(`Error: ${errorMsg}`)
    }
  } catch (e: any) {
    console.log(`Error checking validity: ${e.message}`)
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
