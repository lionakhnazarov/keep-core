import { HardhatRuntimeEnvironment } from "hardhat/types"

async function main() {
  const hre: HardhatRuntimeEnvironment = require("hardhat")
  const { ethers, helpers } = hre
  
  console.log("=== Restoring Chain and Fixing Wallet Owner ===")
  console.log("")
  console.log("⚠️  WARNING: This script will attempt to restore chain state")
  console.log("   If contracts are not accessible, you may need to restart geth")
  console.log("")
  
  // First, try to find a block where contracts exist
  // Start from a high block number and work backwards
  console.log("=== Finding Valid Block ===")
  
  let validBlock = null
  const latestBlock = await ethers.provider.getBlockNumber()
  console.log("Latest block:", latestBlock)
  
  // Try blocks in reverse order
  for (let blockNum = latestBlock; blockNum >= Math.max(0, latestBlock - 1000); blockNum -= 100) {
    try {
      await ethers.provider.send("debug_setHead", [`0x${blockNum.toString(16)}`])
      const wr = await helpers.contracts.getContract("WalletRegistry")
      const walletOwner = await wr.walletOwner()
      
      if (walletOwner && walletOwner !== ethers.constants.AddressZero) {
        validBlock = blockNum
        console.log(`✓ Found valid block: ${blockNum}`)
        break
      }
    } catch (e) {
      // Continue searching
    }
  }
  
  if (!validBlock) {
    console.log("\n❌ Could not find a valid block with contracts")
    console.log("   The chain state may be corrupted")
    console.log("\nSOLUTION: Restart your geth node to restore proper state")
    console.log("   Then run this script again")
    return
  }
  
  // Restore to valid block
  await ethers.provider.send("debug_setHead", [`0x${validBlock.toString(16)}`])
  console.log(`\n✓ Restored to block ${validBlock}`)
  
  // Now proceed with wallet owner fix
  try {
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
    
    // Deploy and set SimpleWalletOwner
    console.log("\n=== Deploying SimpleWalletOwner ===")
    const SimpleWalletOwner = await ethers.getContractFactory("SimpleWalletOwner")
    const [deployer] = await ethers.getSigners()
    const simpleWalletOwner = await SimpleWalletOwner.connect(deployer).deploy()
    await simpleWalletOwner.deployed()
    console.log("✓ Deployed to:", simpleWalletOwner.address)
    
    // Initialize or update
    const wrGov = await helpers.contracts.getContract("WalletRegistryGovernance")
    const owner = await wrGov.owner()
    const signer = await ethers.getSigner(owner)
    const wrGovConnected = wrGov.connect(signer)
    
    if (walletOwner === ethers.constants.AddressZero) {
      console.log("\n=== Initializing Wallet Owner (No Delay) ===")
      const initTx = await wrGovConnected.initializeWalletOwner(simpleWalletOwner.address)
      await initTx.wait()
      console.log("✓ Initialized! Transaction:", initTx.hash)
    } else {
      console.log("\n=== Beginning Update ===")
      const beginTx = await wrGovConnected.beginWalletOwnerUpdate(simpleWalletOwner.address)
      await beginTx.wait()
      console.log("✓ Update initiated. Transaction:", beginTx.hash)
      
      // Check if we can finalize
      const changeInitiated = await wrGov.walletOwnerChangeInitiated()
      const governanceDelay = await wrGov.governanceDelay()
      const currentBlock = await ethers.provider.getBlock("latest")
      const timeElapsed = currentBlock.timestamp - changeInitiated.toNumber()
      
      if (timeElapsed >= governanceDelay.toNumber()) {
        console.log("\n✓ Delay passed! Finalizing...")
        const finalizeTx = await wrGovConnected.finalizeWalletOwnerUpdate()
        await finalizeTx.wait()
        console.log("✓ Finalized! Transaction:", finalizeTx.hash)
      } else {
        console.log(`\n⚠️  Need to wait ${(governanceDelay.toNumber() - timeElapsed).toString()} seconds`)
        console.log("   Or advance time on geth node")
      }
    }
    
    // Verify
    const newWO = await wr.walletOwner()
    const newCode = await ethers.provider.getCode(newWO)
    console.log("\nFinal Wallet Owner:", newWO)
    console.log("Is Contract:", newCode.length > 2)
    
    if (newCode.length > 2) {
      console.log("\n✅ SUCCESS!")
    }
    
  } catch (error: any) {
    console.error("\n❌ Error:", error.message)
    console.log("\nThe chain may need to be restored manually")
    console.log("Consider restarting the geth node")
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
