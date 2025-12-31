import { HardhatRuntimeEnvironment } from "hardhat/types"

async function main() {
  const hre: HardhatRuntimeEnvironment = require("hardhat")
  const { ethers, helpers } = hre
  
  console.log("=== Complete Wallet Owner Fix ===")
  console.log("")
  console.log("⚠️  IMPORTANT: If chain state is corrupted, restart geth first!")
  console.log("   The chain may have been rewound too far.")
  console.log("")
  
  // Check current block
  const currentBlock = await ethers.provider.getBlockNumber()
  console.log("Current block:", currentBlock)
  
  if (currentBlock < 1000) {
    console.log("\n⚠️  WARNING: Block number is very low!")
    console.log("   Chain state may be corrupted from rewinds.")
    console.log("   Recommendation: Restart geth node to restore state")
    console.log("")
    console.log("   Then run this script again, or use faketime approach:")
    console.log("   See: /tmp/restart-geth-with-faketime.sh")
    return
  }
  
  try {
    // Try to access contracts
    const wr = await helpers.contracts.getContract("WalletRegistry")
    const walletOwner = await wr.walletOwner()
    const code = await ethers.provider.getCode(walletOwner)
    const isContract = code.length > 2
    
    console.log("\nCurrent Wallet Owner:", walletOwner)
    console.log("Is Contract:", isContract)
    
    if (isContract) {
      console.log("\n✅ Wallet Owner is already a contract! No action needed.")
      return
    }
    
    // Deploy SimpleWalletOwner
    console.log("\n=== Deploying SimpleWalletOwner ===")
    const SimpleWalletOwner = await ethers.getContractFactory("SimpleWalletOwner")
    const [deployer] = await ethers.getSigners()
    const simpleWalletOwner = await SimpleWalletOwner.connect(deployer).deploy()
    await simpleWalletOwner.deployed()
    console.log("✓ Deployed to:", simpleWalletOwner.address)
    
    // Get governance
    const wrGov = await helpers.contracts.getContract("WalletRegistryGovernance")
    const owner = await wrGov.owner()
    const signer = await ethers.getSigner(owner)
    const wrGovConnected = wrGov.connect(signer)
    
    // Initialize or update
    if (walletOwner === ethers.constants.AddressZero) {
      console.log("\n=== Initializing (No Delay) ===")
      const initTx = await wrGovConnected.initializeWalletOwner(simpleWalletOwner.address)
      await initTx.wait()
      console.log("✓ Initialized! Transaction:", initTx.hash)
    } else {
      console.log("\n=== Beginning Update ===")
      const beginTx = await wrGovConnected.beginWalletOwnerUpdate(simpleWalletOwner.address)
      await beginTx.wait()
      console.log("✓ Update initiated. Transaction:", beginTx.hash)
      
      // Check delay
      const changeInitiated = await wrGov.walletOwnerChangeInitiated()
      const governanceDelay = await wrGov.governanceDelay()
      const block = await ethers.provider.getBlock("latest")
      const timeElapsed = block.timestamp - changeInitiated.toNumber()
      
      console.log("\nGovernance Delay:", governanceDelay.toString(), "seconds")
      console.log("Time Elapsed:", timeElapsed.toString(), "seconds")
      
      if (timeElapsed >= governanceDelay.toNumber()) {
        console.log("\n✓ Delay passed! Finalizing...")
        const finalizeTx = await wrGovConnected.finalizeWalletOwnerUpdate()
        await finalizeTx.wait()
        console.log("✓ Finalized! Transaction:", finalizeTx.hash)
      } else {
        console.log(`\n⚠️  Need to wait ${(governanceDelay.toNumber() - timeElapsed).toString()} seconds`)
        console.log("\nTo advance time:")
        console.log("1. Restart geth with faketime: /tmp/restart-geth-with-faketime.sh")
        console.log("2. Or wait for real time to pass")
        console.log("\nThen finalize with:")
        console.log("  npx hardhat console --network development")
        console.log("  const { ethers, helpers } = require('hardhat');")
        console.log("  const wrGov = await helpers.contracts.getContract('WalletRegistryGovernance');")
        console.log("  const owner = await wrGov.owner();")
        console.log("  await wrGov.connect(await ethers.getSigner(owner)).finalizeWalletOwnerUpdate();")
        return
      }
    }
    
    // Verify
    const newWO = await wr.walletOwner()
    const newCode = await ethers.provider.getCode(newWO)
    console.log("\n=== Final Verification ===")
    console.log("Wallet Owner:", newWO)
    console.log("Is Contract:", newCode.length > 2)
    
    if (newCode.length > 2) {
      console.log("\n✅ SUCCESS! Wallet Owner is now a contract.")
      console.log("   You can now call approveDkgResult successfully!")
    }
    
  } catch (error: any) {
    console.error("\n❌ Error:", error.message)
    console.log("\nThe chain state may be corrupted.")
    console.log("Solutions:")
    console.log("1. Restart geth node to restore state")
    console.log("2. Use faketime to restart geth: /tmp/restart-geth-with-faketime.sh")
    console.log("3. Redeploy contracts if necessary")
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
