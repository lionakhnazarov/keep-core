import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * Decode the DKG result event and test array bounds
 */
async function main() {
  const WalletRegistry = await hre.deployments.get("WalletRegistry")
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address)

  console.log("==========================================")
  console.log("Decoding DKG Result Event and Testing")
  console.log("==========================================")
  console.log(`WalletRegistry: ${WalletRegistry.address}`)
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
  
  console.log(`Event at block: ${latestEvent.blockNumber}`)
  console.log(`Result Hash: ${latestEvent.args.resultHash}`)
  console.log("")
  console.log("DKG Result Details:")
  console.log(`  Submitter Member Index: ${result.submitterMemberIndex.toString()}`)
  console.log(`  Group Public Key Length: ${result.groupPubKey.length} bytes`)
  console.log(`  Misbehaved Members Count: ${result.misbehavedMembersIndices.length}`)
  console.log(`  Signing Members Count: ${result.signingMembersIndices.length}`)
  console.log(`  Total Members Count: ${result.members.length}`)
  console.log(`  Members Hash: ${result.membersHash}`)
  console.log("")

  // Check for potential array bounds issues
  console.log("=== Array Bounds Check ===")
  
  const submitterIndex = result.submitterMemberIndex.toNumber()
  console.log(`Submitter Index: ${submitterIndex}`)
  
  if (submitterIndex === 0) {
    console.error("❌ CRITICAL: submitterMemberIndex is 0!")
    console.error("   This would cause underflow: submitterIndex - 1")
    console.error("   Solidity 0.8+ reverts on underflow with empty error data")
  } else if (submitterIndex > result.members.length) {
    console.error(`❌ CRITICAL: submitterMemberIndex (${submitterIndex}) > members.length (${result.members.length})`)
    console.error("   This would cause array out of bounds access")
  } else {
    console.log(`✓ Submitter index is valid (1-${result.members.length})`)
  }
  
  console.log("")
  console.log("Misbehaved Members Indices:")
  let hasInvalidIndex = false
  for (let i = 0; i < result.misbehavedMembersIndices.length; i++) {
    const idx = result.misbehavedMembersIndices[i]
    const arrayIndex = idx - 1
    if (idx === 0) {
      console.error(`  ❌ Index ${i}: value is 0 (would cause underflow)`)
      hasInvalidIndex = true
    } else if (idx > result.members.length) {
      console.error(`  ❌ Index ${i}: value ${idx} > members.length (${result.members.length})`)
      hasInvalidIndex = true
    } else {
      console.log(`  ✓ Index ${i}: ${idx} (array access: ${arrayIndex})`)
    }
  }
  
  if (!hasInvalidIndex && result.misbehavedMembersIndices.length > 0) {
    console.log("✓ All misbehaved member indices are valid")
  }
  
  console.log("")
  console.log("Signing Members Indices:")
  for (let i = 0; i < Math.min(result.signingMembersIndices.length, 10); i++) {
    const idx = result.signingMembersIndices[i].toNumber()
    console.log(`  Index ${i}: ${idx}`)
  }
  if (result.signingMembersIndices.length > 10) {
    console.log(`  ... and ${result.signingMembersIndices.length - 10} more`)
  }
  
  console.log("")
  console.log("=== Testing Approval ===")
  
  const [deployer] = await ethers.getSigners()
  const wrConnected = wr.connect(deployer)
  
  try {
    await wrConnected.callStatic.approveDkgResult(result)
    console.log("✅ Approval would succeed!")
  } catch (error: any) {
    console.log("❌ Approval failed:")
    console.log(`   Message: ${error.message}`)
    
    if (error.data && error.data !== "0x") {
      console.log(`   Data: ${error.data}`)
    } else if (error.data === "0x") {
      console.log(`   Data: 0x (empty - likely array bounds or assert failure)`)
    }
    
    // Check if it's an array bounds issue
    if (submitterIndex === 0 || submitterIndex > result.members.length) {
      console.log("")
      console.log("🔍 LIKELY CAUSE: Array bounds violation in approveResult()")
      console.log(`   Line 353: result.members[${submitterIndex} - 1]`)
      console.log(`   This would access index ${submitterIndex - 1} in array of length ${result.members.length}`)
    }
    
    if (hasInvalidIndex) {
      console.log("")
      console.log("🔍 LIKELY CAUSE: Array bounds violation in misbehaved members loop")
      console.log("   Line 372: result.members[misbehavedMembersIndices[i] - 1]")
    }
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})


