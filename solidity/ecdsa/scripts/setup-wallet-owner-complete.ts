import { HardhatRuntimeEnvironment } from "hardhat/types"

async function main() {
  const hre: HardhatRuntimeEnvironment = require("hardhat")
  const { ethers, helpers } = hre
  
  console.log("=== Complete Wallet Owner Setup ===")
  console.log("")
  
  // Use helpers to get contracts (works with deployed addresses)
  let wr, wrGov
  try {
    wr = await helpers.contracts.getContract("WalletRegistry")
    wrGov = await helpers.contracts.getContract("WalletRegistryGovernance")
    console.log("✓ Contracts accessible!")
    console.log("WalletRegistry:", wr.address)
    console.log("WalletRegistryGovernance:", wrGov.address)
  } catch (error: any) {
    console.log("\n⚠️  Could not access contracts")
    console.log("Error:", error.message)
    console.log("")
    console.log("OPTIONS:")
    console.log("1. Redeploy contracts: yarn deploy --network development")
    console.log("2. Restore chain state from backup")
    console.log("")
    console.log("After contracts exist, run this script again.")
    return
  }
  
  const walletOwner = await wr.walletOwner()
  const woCode = await ethers.provider.getCode(walletOwner)
  const isContract = woCode.length > 2
  
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
  
  // Get governance owner
  const owner = await wrGov.owner()
  const signer = await ethers.getSigner(owner)
  const wrGovConnected = wrGov.connect(signer)
  
  // Initialize or update
  if (walletOwner === ethers.constants.AddressZero) {
    console.log("\n=== Initializing Wallet Owner (No Delay) ===")
    const initTx = await wrGovConnected.initializeWalletOwner(simpleWalletOwner.address)
    await initTx.wait()
    console.log("✓ Initialized! Transaction:", initTx.hash)
  } else {
    console.log("\n=== Beginning Wallet Owner Update ===")
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
      const remaining = governanceDelay.toNumber() - timeElapsed
      console.log(`\n⚠️  Need to wait ${remaining.toString()} seconds (${(remaining / 3600).toFixed(2)} hours)`)
      console.log("")
      console.log("To advance time:")
      console.log("1. Restart geth with faketime:")
      console.log("   bash /tmp/restart-geth-with-faketime.sh")
      console.log("2. Mine a block (geth auto-mines)")
      console.log("3. Run this script again to finalize")
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
  } else {
    console.log("\n⚠️  Wallet Owner is still not a contract")
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
