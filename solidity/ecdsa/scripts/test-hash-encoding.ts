import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * Test different ways of encoding the DKG result to find the issue
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
  console.log("Testing Hash Encoding")
  console.log("==========================================")
  console.log("")
  
  // Method 1: Direct encoding (what we've been using)
  const hash1 = ethers.utils.keccak256(
    ethers.utils.defaultAbiCoder.encode(
      [
        "tuple(uint256 submitterMemberIndex, bytes groupPubKey, uint8[] misbehavedMembersIndices, bytes signatures, uint256[] signingMembersIndices, uint32[] members, bytes32 membersHash)",
      ],
      [result]
    )
  )
  
  console.log(`Method 1 (direct): ${hash1}`)
  
  // Method 2: Using the interface to encode
  const iface = new ethers.utils.Interface([
    "function approveDkgResult(tuple(uint256 submitterMemberIndex, bytes groupPubKey, uint8[] misbehavedMembersIndices, bytes signatures, uint256[] signingMembersIndices, uint32[] members, bytes32 membersHash) dkgResult)",
  ])
  
  const encoded = iface.encodeFunctionData("approveDkgResult", [result])
  // Extract just the data part (skip function selector)
  const dataOnly = encoded.slice(10) // Remove 0x + 4 bytes selector
  
  // The hash should be of just the struct, not the function call
  // So we need to decode the data first
  const decoded = ethers.utils.defaultAbiCoder.decode(
    ["tuple(uint256 submitterMemberIndex, bytes groupPubKey, uint8[] misbehavedMembersIndices, bytes signatures, uint256[] signingMembersIndices, uint32[] members, bytes32 membersHash)"],
    "0x" + dataOnly
  )
  
  const hash2 = ethers.utils.keccak256(
    ethers.utils.defaultAbiCoder.encode(
      [
        "tuple(uint256 submitterMemberIndex, bytes groupPubKey, uint8[] misbehavedMembersIndices, bytes signatures, uint256[] signingMembersIndices, uint32[] members, bytes32 membersHash)",
      ],
      decoded
    )
  )
  
  console.log(`Method 2 (via interface): ${hash2}`)
  console.log("")
  
  if (hash1 === hash2) {
    console.log("✅ Both methods produce same hash")
  } else {
    console.log("❌ Hashes differ!")
  }
  
  console.log("")
  console.log("Event hash:", latestEvent.args.resultHash || hash1)
  console.log("")
  
  // Check if the struct fields match what we expect
  console.log("Struct fields:")
  console.log(`  submitterMemberIndex: ${result.submitterMemberIndex.toString()}`)
  console.log(`  groupPubKey length: ${result.groupPubKey.length} bytes`)
  console.log(`  misbehavedMembersIndices: ${result.misbehavedMembersIndices.length} items`)
  console.log(`  signatures length: ${result.signatures.length} bytes`)
  console.log(`  signingMembersIndices: ${result.signingMembersIndices.length} items`)
  console.log(`  members: ${result.members.length} items`)
  console.log(`  membersHash: ${result.membersHash}`)
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
