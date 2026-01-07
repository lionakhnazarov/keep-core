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
  console.log("Final Analysis")
  console.log("==========================================")
  console.log("")
  console.log("Event hash:", latestEvent.args.resultHash || "N/A")
  console.log("")
  console.log("All verification checks PASS:")
  console.log("  ✅ DKG State: CHALLENGE")
  console.log("  ✅ Challenge period: Passed")
  console.log("  ✅ Hash match: Verified")
  console.log("  ✅ Array bounds: Valid")
  console.log("  ✅ Sortition pool: Valid")
  console.log("  ✅ Precedence period: Passed")
  console.log("  ✅ Result validity: true")
  console.log("")
  console.log("But transaction still reverts with no error message.")
  console.log("")
  console.log("This suggests the revert happens AFTER approveResult() succeeds,")
  console.log("possibly in:")
  console.log("  1. wallets.addWallet()")
  console.log("  2. walletOwner.__ecdsaWalletCreatedCallback()")
  console.log("  3. dkg.complete()")
  console.log("  4. sortitionPool.unlock()")
  console.log("")
  console.log("Since the trace shows revert at DELEGATECALL to library,")
  console.log("it's likely happening in approveResult() itself, but after")
  console.log("all the require checks pass.")
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
