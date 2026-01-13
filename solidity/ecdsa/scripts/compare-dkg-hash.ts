import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * Compare the DKG result hash from the event with the calculated hash
 * to verify if the encoding matches.
 */
async function main() {
  console.log("==========================================")
  console.log("DKG Result Hash Comparison")
  console.log("==========================================")
  console.log("")

  const WalletRegistry = await hre.deployments.get("WalletRegistry")
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address)

  // Get DKG result submission event
  const filter = wr.filters.DkgResultSubmitted()
  const currentBlock = await ethers.provider.getBlockNumber()
  const fromBlock = Math.max(0, currentBlock - 5000)
  const events = await wr.queryFilter(filter, fromBlock, currentBlock)
  
  if (events.length === 0) {
    console.error("Error: Could not find DKG result submission event")
    process.exit(1)
  }

  const latestEvent = events[events.length - 1]
  const eventHash = latestEvent.args.resultHash
  const result = latestEvent.args.result
  
  console.log(`Found DKG result submission at block ${latestEvent.blockNumber}`)
  console.log(`Event Result Hash: ${eventHash}`)
  console.log("")

  // Calculate hash using same method as contract: keccak256(abi.encode(result))
  // Field order must match struct definition:
  // 1. submitterMemberIndex (uint256)
  // 2. groupPubKey (bytes)
  // 3. misbehavedMembersIndices (uint8[])
  // 4. signatures (bytes)
  // 5. signingMembersIndices (uint256[])
  // 6. members (uint32[])
  // 7. membersHash (bytes32) <- MUST BE LAST
  
  const calculatedHash = ethers.utils.keccak256(
    ethers.utils.defaultAbiCoder.encode(
      ["tuple(uint256,bytes,uint8[],bytes,uint256[],uint32[],bytes32)"],
      [[
        result.submitterMemberIndex,
        result.groupPubKey,
        result.misbehavedMembersIndices,
        result.signatures,
        result.signingMembersIndices,
        result.members,
        result.membersHash
      ]]
    )
  )

  console.log("Calculated Hash (from event data):", calculatedHash)
  console.log("")

  const match = eventHash.toLowerCase() === calculatedHash.toLowerCase()
  
  console.log("==========================================")
  if (match) {
    console.log("✅ HASHES MATCH!")
    console.log("==========================================")
    console.log("")
    console.log("The event data encoding is correct.")
    console.log("The hash from the event matches our calculation.")
    console.log("")
    console.log("This means:")
    console.log("  - Event data structure is correct")
    console.log("  - Field order is correct")
    console.log("  - Data types are correct")
    console.log("")
    console.log("If approval still fails, the issue is likely:")
    console.log("  - sortitionPool.unlock() reverting")
    console.log("  - walletOwner callback failing")
    console.log("  - Other validation checks")
  } else {
    console.log("❌ HASH MISMATCH!")
    console.log("==========================================")
    console.log("")
    console.log("The event hash doesn't match our calculation.")
    console.log("")
    console.log("Event hash:    ", eventHash)
    console.log("Calculated:    ", calculatedHash)
    console.log("")
    console.log("Possible causes:")
    console.log("  1. Field order mismatch in encoding")
    console.log("  2. Data type mismatch")
    console.log("  3. Array encoding issue")
    console.log("  4. Bytes encoding issue")
  }
  console.log("")
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})


