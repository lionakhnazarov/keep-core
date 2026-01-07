import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * Extract exact DKG result data from submission event
 * Outputs JSON that can be used in Go tests
 */
async function main() {
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
  const eventResult = latestEvent.args.result
  
  // Output as JSON for Go script
  const resultData = {
    submitterMemberIndex: eventResult.submitterMemberIndex.toString(),
    groupPubKey: eventResult.groupPubKey,
    misbehavedMembersIndices: eventResult.misbehavedMembersIndices.map((x: any) => x.toString()),
    signatures: eventResult.signatures,
    signingMembersIndices: eventResult.signingMembersIndices.map((x: any) => x.toString()),
    members: eventResult.members.map((x: any) => x.toString()),
    membersHash: eventResult.membersHash,
    storedHash: latestEvent.args.resultHash,
    submissionBlock: latestEvent.blockNumber.toString(),
  }
  
  console.log(JSON.stringify(resultData, null, 2))
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

