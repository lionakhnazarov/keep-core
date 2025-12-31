import { HardhatRuntimeEnvironment } from "hardhat/types"

async function main() {
  const hre: HardhatRuntimeEnvironment = require("hardhat")
  const { ethers, helpers } = hre
  
  console.log("=== Governance Status Check ===\n")
  
  const wr = await helpers.contracts.getContract("WalletRegistry")
  const wrGov = await helpers.contracts.getContract("WalletRegistryGovernance")
  
  const delay = await wrGov.governanceDelay()
  const changeInitiated = await wrGov.governanceDelayChangeInitiated()
  const pendingValue = await wrGov.newGovernanceDelay()
  
  console.log("Current governanceDelay:", delay.toString(), "seconds")
  console.log("Change initiated:", changeInitiated.toString())
  console.log("Pending new value:", pendingValue.toString())
  
  if (changeInitiated.gt(0)) {
    const block = await ethers.provider.getBlock("latest")
    const blockTimestamp = (block.timestamp as any).toNumber ? (block.timestamp as any).toNumber() : Number(block.timestamp)
    const elapsed = blockTimestamp - changeInitiated.toNumber()
    const remaining = delay.toNumber() - elapsed
    console.log("\nTime elapsed:", elapsed.toString(), "seconds")
    console.log("Remaining:", remaining.toString(), "seconds")
    console.log("Blocks needed: ~", Math.ceil(remaining / 15))
  }
  
  const wo = await wr.walletOwner()
  const woCode = await ethers.provider.getCode(wo)
  console.log("\nWallet Owner:", wo)
  console.log("Is Contract:", woCode.length > 2)
  
  const params = await wr.dkgParameters()
  console.log("Challenge Period:", params.resultChallengePeriodLength.toString(), "blocks")
  
  console.log("\n=== Summary ===")
  if (woCode.length > 2 && delay.lte(60) && params.resultChallengePeriodLength.eq(100)) {
    console.log("✅ All governance parameters are configured!")
  } else {
    console.log("⚠️  Some parameters need configuration:")
    if (woCode.length <= 2) console.log("  - Wallet Owner is not a contract")
    if (delay.gt(60)) console.log("  - Governance delay is still high (", delay.toString(), "seconds)")
    if (!params.resultChallengePeriodLength.eq(100)) console.log("  - Challenge period is not 100 blocks")
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
