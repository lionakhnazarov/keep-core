import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * Compare how Go client would encode vs event data encoding
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
  
  console.log("==========================================")
  console.log("Comparing Encoding Methods")
  console.log("==========================================")
  console.log("")
  
  // Method 1: Direct encoding (what Hardhat/ethers does)
  const hash1 = ethers.utils.keccak256(
    ethers.utils.defaultAbiCoder.encode(
      [
        "tuple(uint256 submitterMemberIndex, bytes groupPubKey, uint8[] misbehavedMembersIndices, bytes signatures, uint256[] signingMembersIndices, uint32[] members, bytes32 membersHash)",
      ],
      [result]
    )
  )
  
  console.log(`Event hash: ${latestEvent.args.resultHash || hash1}`)
  console.log(`Calculated hash: ${hash1}`)
  console.log(`Match: ${latestEvent.args.resultHash === hash1 ? "✅ YES" : "❌ NO"}`)
  console.log("")
  
  // Check if there's any difference in how arrays are encoded
  console.log("Checking array encoding...")
  console.log(`  signingMembersIndices type: ${typeof result.signingMembersIndices[0]}`)
  console.log(`  signingMembersIndices[0]: ${result.signingMembersIndices[0].toString()}`)
  console.log(`  members type: ${typeof result.members[0]}`)
  console.log(`  members[0]: ${result.members[0]}`)
  console.log("")
  
  // Try encoding with explicit BigNumber conversion
  const convertedResult = {
    submitterMemberIndex: result.submitterMemberIndex,
    groupPubKey: result.groupPubKey,
    misbehavedMembersIndices: result.misbehavedMembersIndices,
    signatures: result.signatures,
    signingMembersIndices: result.signingMembersIndices.map((x: any) => 
      ethers.BigNumber.from(x.toString())
    ),
    members: result.members,
    membersHash: result.membersHash,
  }
  
  const hash2 = ethers.utils.keccak256(
    ethers.utils.defaultAbiCoder.encode(
      [
        "tuple(uint256 submitterMemberIndex, bytes groupPubKey, uint8[] misbehavedMembersIndices, bytes signatures, uint256[] signingMembersIndices, uint32[] members, bytes32 membersHash)",
      ],
      [convertedResult]
    )
  )
  
  console.log(`Hash with explicit conversion: ${hash2}`)
  console.log(`Match: ${hash1 === hash2 ? "✅ YES" : "❌ NO"}`)
  console.log("")
  
  // The issue might be that when the Go client calls it, something else fails
  // Let's check what happens if we try to call isDkgResultValid first
  console.log("Testing isDkgResultValid call...")
  try {
    const [isValid, errorMsg] = await wr.isDkgResultValid(result)
    console.log(`  Is valid: ${isValid}`)
    if (!isValid) {
      console.log(`  Error: ${errorMsg}`)
    } else {
      console.log("  ✅ Result is valid")
    }
  } catch (e: any) {
    console.log(`  ❌ Call failed: ${e.message}`)
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
