import { ethers } from "hardhat"
import hre from "hardhat"

async function main() {
  console.log("==========================================")
  console.log("Check DKG Result Hash Mismatch")
  console.log("==========================================")
  console.log("")

  const WalletRegistry = await hre.deployments.get("WalletRegistry")
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address)

  // Get current state
  const state = await wr.getWalletCreationState()
  console.log(`Current DKG State: ${state} (3 = CHALLENGE)`)
  console.log("")

  if (state !== 3) {
    console.error("Error: DKG is not in CHALLENGE state")
    process.exit(1)
  }

  // Get DKG result submission event
  console.log("Searching for DKG result submission event...")
  const filter = wr.filters.DkgResultSubmitted()
  const currentBlock = await ethers.provider.getBlockNumber()
  const fromBlock = Math.max(0, currentBlock - 5000)
  const events = await wr.queryFilter(filter, fromBlock, currentBlock)
  
  if (events.length === 0) {
    console.error("Error: Could not find DKG result submission event")
    process.exit(1)
  }

  const latestEvent = events[events.length - 1]
  console.log(`Found DKG result submission at block ${latestEvent.blockNumber}`)
  console.log("")

  // Get the result from the event
  const eventResult = latestEvent.args.result
  const eventHash = latestEvent.args.resultHash
  console.log(`Event Result Hash: ${eventHash}`)
  console.log("")

  // Compute hash from the result
  console.log("Computing hash from event result...")
  console.log("")
  
  // The result structure is:
  // struct Result {
  //   uint256 submitterMemberIndex;
  //   bytes groupPubKey;
  //   bytes32 membersHash;
  //   uint8[] misbehavedMembersIndices;  // NOTE: uint8[], not uint32[]!
  //   bytes signatures;
  //   uint32[] signingMembersIndices;
  //   uint32[] members;
  // }
  
  const { keccak256, defaultAbiCoder } = ethers.utils
  const abiCoder = defaultAbiCoder
  
  // Convert misbehavedMembersIndices from uint32[] to uint8[]
  // Event decoding might return them as numbers, so convert properly
  const misbehavedMembersIndices = eventResult.misbehavedMembersIndices.map((x: any) => {
    const val = typeof x === 'bigint' ? Number(x) : x
    return val
  })
  
  // Encode the result struct with correct types
  const encodedResult = abiCoder.encode(
    [
      "tuple(uint256,bytes,bytes32,uint8[],bytes,uint32[],uint32[])"
    ],
    [
      [
        eventResult.submitterMemberIndex,
        eventResult.groupPubKey,
        eventResult.membersHash,
        misbehavedMembersIndices,
        eventResult.signatures,
        eventResult.signingMembersIndices,
        eventResult.members
      ]
    ]
  )
  
  const computedHash = keccak256(encodedResult)
  console.log(`Computed Hash: ${computedHash}`)
  console.log("")

  // Compare hashes
  console.log("==========================================")
  if (computedHash.toLowerCase() === eventHash.toLowerCase()) {
    console.log("✅ HASHES MATCH!")
    console.log("")
    console.log("The result hash from the event matches the computed hash.")
    console.log("The approval failure is likely due to:")
    console.log("  1. The stored hash in the contract is different")
    console.log("  2. Other validation checks in approveResult()")
  } else {
    console.log("❌ HASHES DO NOT MATCH!")
    console.log("")
    console.log("This is the problem! The result hash doesn't match.")
    console.log("")
    console.log("Possible causes:")
    console.log("  1. Result structure changed between submission and approval")
    console.log("  2. Encoding/decoding issue")
    console.log("  3. Event data doesn't match what was actually submitted")
  }
  console.log("==========================================")
  console.log("")

  // Try to get the stored hash from the contract
  console.log("Checking stored hash in contract...")
  console.log("")
  
  // The contract stores submittedResultHash, but we can't read it directly
  // Let's check if we can get it from the event or try to call a view function
  try {
    // Try to get it via a low-level call or check the event args
    console.log("Event args:")
    console.log(`  resultHash: ${eventHash}`)
    console.log(`  seed: ${latestEvent.args.seed.toString()}`)
    console.log("")
    
    // Check result details
    console.log("Result details:")
    console.log(`  submitterMemberIndex: ${eventResult.submitterMemberIndex.toString()}`)
    console.log(`  groupPubKey length: ${eventResult.groupPubKey.length} bytes`)
    console.log(`  membersHash: ${eventResult.membersHash}`)
    console.log(`  misbehavedMembersIndices: ${eventResult.misbehavedMembersIndices.length}`)
    console.log(`  signatures length: ${eventResult.signatures.length} bytes`)
    console.log(`  signingMembersIndices: ${eventResult.signingMembersIndices.length}`)
    console.log(`  members: ${eventResult.members.length}`)
    console.log("")
    
    // Try to verify the hash matches what's stored
    // We can't directly read submittedResultHash, but we can check if approval would work
    console.log("To verify the stored hash matches:")
    console.log("  1. The event hash should match what's stored")
    console.log("  2. If hashes match but approval fails, check other validations")
    console.log("")
    
  } catch (error: any) {
    console.error("Error checking stored hash:", error.message)
  }

  // Show what the result looks like for debugging
  console.log("")
  console.log("Result structure for debugging:")
  console.log(JSON.stringify({
    submitterMemberIndex: eventResult.submitterMemberIndex.toString(),
    groupPubKey: eventResult.groupPubKey,
    membersHash: eventResult.membersHash,
    misbehavedMembersIndices: eventResult.misbehavedMembersIndices.map((x: any) => x.toString()),
    signatures: eventResult.signatures,
    signingMembersIndices: eventResult.signingMembersIndices.map((x: any) => x.toString()),
    members: eventResult.members.map((x: any) => x.toString())
  }, null, 2))
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

