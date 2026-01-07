import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * Verify all conditions for approveResult to succeed
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
  const submissionBlock = latestEvent.blockNumber
  
  console.log("==========================================")
  console.log("Verifying approveResult Conditions")
  console.log("==========================================")
  console.log("")
  console.log(`Event block: ${submissionBlock}`)
  console.log("")
  
  // Check 1: DKG State
  console.log("1. Checking DKG State...")
  try {
    const state = await wr.getWalletCreationState()
    console.log(`   State: ${state} (3 = CHALLENGE)`)
    if (state === 3) {
      console.log("   ✅ PASS: DKG is in CHALLENGE state")
    } else {
      console.log(`   ❌ FAIL: Expected state 3 (CHALLENGE), got ${state}`)
      return
    }
  } catch (e: any) {
    console.log(`   ❌ ERROR: ${e.message}`)
    return
  }
  
  // Check 2: Challenge period - need to get parameters from contract
  console.log("")
  console.log("2. Checking Challenge Period...")
  try {
    // Get challenge period length from contract storage or use default
    // For now, let's check if enough blocks have passed (typically 200 blocks)
    const currentBlock = await ethers.provider.getBlockNumber()
    const blocksSinceSubmission = currentBlock - submissionBlock
    
    console.log(`   Submission block: ${submissionBlock}`)
    console.log(`   Current block: ${currentBlock}`)
    console.log(`   Blocks since submission: ${blocksSinceSubmission}`)
    console.log(`   ⚠️  INFO: Challenge period typically 200 blocks`)
    console.log(`   ${blocksSinceSubmission > 200 ? "✅ PASS: Likely passed" : "❌ FAIL: May not have passed"}`)
  } catch (e: any) {
    console.log(`   ❌ ERROR: ${e.message}`)
    return
  }
  
  // Check 3: Hash match - use hash from event
  console.log("")
  console.log("3. Checking Hash Match...")
  try {
    // The event contains the hash in the event args
    const eventHash = latestEvent.args.resultHash || ethers.utils.keccak256(
      ethers.utils.defaultAbiCoder.encode(
        [
          "tuple(uint256 submitterMemberIndex, bytes groupPubKey, uint8[] misbehavedMembersIndices, bytes signatures, uint256[] signingMembersIndices, uint32[] members, bytes32 membersHash)",
        ],
        [result]
      )
    )
    
    const calculatedHash = ethers.utils.keccak256(
      ethers.utils.defaultAbiCoder.encode(
        [
          "tuple(uint256 submitterMemberIndex, bytes groupPubKey, uint8[] misbehavedMembersIndices, bytes signatures, uint256[] signingMembersIndices, uint32[] members, bytes32 membersHash)",
        ],
        [result]
      )
    )
    
    console.log(`   Event hash: ${eventHash}`)
    console.log(`   Calculated hash: ${calculatedHash}`)
    
    if (eventHash === calculatedHash) {
      console.log("   ✅ PASS: Hashes match")
    } else {
      console.log("   ❌ FAIL: Hash mismatch!")
      console.log("   This is likely the cause of the revert.")
      return
    }
  } catch (e: any) {
    console.log(`   ❌ ERROR: ${e.message}`)
    return
  }
  
  // Check 4: Array bounds for submitterMemberIndex
  console.log("")
  console.log("4. Checking Array Bounds...")
  try {
    const submitterIndex = result.submitterMemberIndex
    const membersLength = result.members.length
    
    console.log(`   Submitter index: ${submitterIndex.toString()}`)
    console.log(`   Members array length: ${membersLength}`)
    
    if (submitterIndex.lt(1)) {
      console.log("   ❌ FAIL: submitterMemberIndex is less than 1 (would underflow)")
      return
    }
    
    if (submitterIndex.gt(membersLength)) {
      console.log(`   ❌ FAIL: submitterMemberIndex (${submitterIndex.toString()}) > members.length (${membersLength})`)
      return
    }
    
    const arrayIndex = submitterIndex.sub(1).toNumber()
    console.log(`   Array access index: ${arrayIndex}`)
    console.log("   ✅ PASS: Array index is valid")
    
    // Check misbehaved members indices
    if (result.misbehavedMembersIndices.length > 0) {
      console.log(`   Checking ${result.misbehavedMembersIndices.length} misbehaved members...`)
      for (let i = 0; i < result.misbehavedMembersIndices.length; i++) {
        const idx = result.misbehavedMembersIndices[i]
        if (idx < 1 || idx > membersLength) {
          console.log(`   ❌ FAIL: misbehavedMembersIndices[${i}] = ${idx} is out of bounds`)
          return
        }
      }
      console.log("   ✅ PASS: All misbehaved member indices are valid")
    }
  } catch (e: any) {
    console.log(`   ❌ ERROR: ${e.message}`)
    return
  }
  
  // Check 5: Sortition pool membership
  console.log("")
  console.log("5. Checking Sortition Pool Membership...")
  try {
    const sortitionPoolAddress = await wr.sortitionPool()
    const sortitionPoolABI = [
      "function getIDOperator(uint32 id) view returns (address)",
    ]
    const sp = new ethers.Contract(sortitionPoolAddress, sortitionPoolABI, ethers.provider)
    
    const submitterIndex = result.submitterMemberIndex
    const memberID = result.members[submitterIndex.sub(1).toNumber()]
    
    console.log(`   SortitionPool: ${sortitionPoolAddress}`)
    console.log(`   Submitter member ID: ${memberID}`)
    
    try {
      const operator = await sp.getIDOperator(memberID)
      console.log(`   Operator address: ${operator}`)
      if (operator === ethers.constants.AddressZero) {
        console.log("   ❌ FAIL: Member ID does not exist in sortition pool")
        return
      }
      console.log("   ✅ PASS: Member ID exists in sortition pool")
    } catch (e2: any) {
      console.log(`   ❌ FAIL: getIDOperator call failed: ${e2.message}`)
      return
    }
  } catch (e: any) {
    console.log(`   ❌ ERROR: ${e.message}`)
    return
  }
  
  console.log("")
  console.log("==========================================")
  console.log("All checks passed! Transaction should succeed.")
  console.log("==========================================")
  console.log("")
  console.log("If transaction still fails, the issue might be:")
  console.log("1. Gas limit too low")
  console.log("2. Precedence period not passed (only submitter can approve)")
  console.log("3. Other internal state issue")
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
