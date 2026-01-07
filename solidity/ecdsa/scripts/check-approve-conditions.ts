import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * Check each condition in approveResult to find which one fails
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
  console.log("Checking approveResult Conditions")
  console.log("==========================================")
  console.log("")
  
  // Check 1: DKG State
  try {
    const state = await wr.getDkgState()
    console.log(`1. DKG State: ${state}`)
    console.log(`   Expected: 3 (CHALLENGE)`)
    console.log(`   ${state === 3 ? "✅ PASS" : "❌ FAIL"}`)
  } catch (e: any) {
    console.log(`1. DKG State check failed: ${e.message}`)
  }
  
  // Check 2: Challenge period
  try {
    const submittedBlock = await wr.getDkgResultSubmissionBlock()
    const challengePeriodLength = await wr.getDkgResultChallengePeriodLength()
    const challengePeriodEnd = submittedBlock.add(challengePeriodLength)
    const currentBlock = await ethers.provider.getBlockNumber()
    
    console.log(`2. Challenge Period:`)
    console.log(`   Submitted block: ${submittedBlock.toString()}`)
    console.log(`   Challenge period length: ${challengePeriodLength.toString()}`)
    console.log(`   Challenge period end: ${challengePeriodEnd.toString()}`)
    console.log(`   Current block: ${currentBlock}`)
    console.log(`   ${currentBlock > challengePeriodEnd.toNumber() ? "✅ PASS" : "❌ FAIL"}`)
  } catch (e: any) {
    console.log(`2. Challenge period check failed: ${e.message}`)
  }
  
  // Check 3: Hash match
  try {
    const submittedHash = await wr.getSubmittedDkgResultHash()
    const calculatedHash = ethers.utils.keccak256(
      ethers.utils.defaultAbiCoder.encode(
        [
          "tuple(uint256 submitterMemberIndex, bytes groupPubKey, uint8[] misbehavedMembersIndices, bytes signatures, uint256[] signingMembersIndices, uint32[] members, bytes32 membersHash)",
        ],
        [result]
      )
    )
    
    console.log(`3. Hash Match:`)
    console.log(`   Submitted hash: ${submittedHash}`)
    console.log(`   Calculated hash: ${calculatedHash}`)
    console.log(`   ${submittedHash === calculatedHash ? "✅ PASS" : "❌ FAIL"}`)
  } catch (e: any) {
    console.log(`3. Hash check failed: ${e.message}`)
  }
  
  // Check 4: Submitter member access
  try {
    const submitterIndex = result.submitterMemberIndex
    const membersLength = result.members.length
    
    console.log(`4. Submitter Member Access:`)
    console.log(`   Submitter index: ${submitterIndex.toString()}`)
    console.log(`   Members length: ${membersLength}`)
    console.log(`   Array access index: ${submitterIndex.sub(1).toString()}`)
    
    if (submitterIndex.lt(1) || submitterIndex.gt(membersLength)) {
      console.log(`   ❌ FAIL: Index out of bounds!`)
    } else {
      console.log(`   ✅ PASS: Index is valid`)
      
      // Try to get operator
      const memberID = result.members[submitterIndex.sub(1).toNumber()]
      const sortitionPool = await wr.sortitionPool()
      const sortitionPoolABI = [
        "function getIDOperator(uint32 id) view returns (address)",
      ]
      const sp = new ethers.Contract(sortitionPool, sortitionPoolABI, ethers.provider)
      
      try {
        const operator = await sp.getIDOperator(memberID)
        console.log(`   Operator address: ${operator}`)
        console.log(`   ✅ PASS: getIDOperator succeeded`)
      } catch (e2: any) {
        console.log(`   ❌ FAIL: getIDOperator failed: ${e2.message}`)
      }
    }
  } catch (e: any) {
    console.log(`4. Submitter member check failed: ${e.message}`)
  }
  
  // Check 5: Precedence period
  try {
    const [deployer] = await ethers.getSigners()
    const submittedBlock = await wr.getDkgResultSubmissionBlock()
    const challengePeriodLength = await wr.getDkgResultChallengePeriodLength()
    const precedencePeriodLength = await wr.getDkgResultSubmitterPrecedencePeriodLength()
    const challengePeriodEnd = submittedBlock.add(challengePeriodLength)
    const precedencePeriodEnd = challengePeriodEnd.add(precedencePeriodLength)
    const currentBlock = await ethers.provider.getBlockNumber()
    
    console.log(`5. Precedence Period:`)
    console.log(`   Precedence period end: ${precedencePeriodEnd.toString()}`)
    console.log(`   Current block: ${currentBlock}`)
    console.log(`   Can approve: ${currentBlock > precedencePeriodEnd.toNumber() ? "Anyone" : "Only submitter"}`)
  } catch (e: any) {
    console.log(`5. Precedence period check failed: ${e.message}`)
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
