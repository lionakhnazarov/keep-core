import { HardhatRuntimeEnvironment } from "hardhat/types"

async function main() {
  const hre: HardhatRuntimeEnvironment = require("hardhat")
  const { ethers, helpers } = hre
  
  console.log("=== Fixing Wallet Owner (Development Workaround) ===")
  console.log("")
  console.log("This script will:")
  console.log("1. Deploy SimpleWalletOwner contract")
  console.log("2. Set it as walletOwner via governance")
  console.log("")
  console.log("⚠️  NOTE: Due to governance delay, you'll need to either:")
  console.log("   - Wait 7 days for the delay to pass")
  console.log("   - Advance time on your geth node")
  console.log("   - Restart geth with modified system time")
  console.log("")
  
  try {
    // Deploy SimpleWalletOwner
    console.log("=== Step 1: Deploying SimpleWalletOwner ===")
    const SimpleWalletOwner = await ethers.getContractFactory("SimpleWalletOwner")
    const [deployer] = await ethers.getSigners()
    const simpleWalletOwner = await SimpleWalletOwner.connect(deployer).deploy()
    await simpleWalletOwner.deployed()
    
    console.log("✓ SimpleWalletOwner deployed to:", simpleWalletOwner.address)
    
    const code = await ethers.provider.getCode(simpleWalletOwner.address)
    if (code.length <= 2) {
      throw new Error("Deployed address is not a contract!")
    }
    console.log("✓ Verified: Contract has code")
    
    // Get governance
    const wrGov = await helpers.contracts.getContract("WalletRegistryGovernance")
    const wr = await helpers.contracts.getContract("WalletRegistry")
    const owner = await wrGov.owner()
    const signer = await ethers.getSigner(owner)
    const wrGovConnected = wrGov.connect(signer)
    
    // Check current state
    console.log("\n=== Step 2: Checking Current State ===")
    let currentWalletOwner
    try {
      currentWalletOwner = await wr.walletOwner()
      console.log("Current Wallet Owner:", currentWalletOwner)
      
      const currentCode = await ethers.provider.getCode(currentWalletOwner)
      const isContract = currentCode.length > 2
      console.log("Is Contract:", isContract)
      
      if (isContract) {
        console.log("\n✅ Wallet Owner is already a contract! No action needed.")
        return
      }
    } catch (e) {
      console.log("⚠️  Could not read walletOwner (chain may be in inconsistent state)")
      console.log("   Current wallet owner may be uninitialized")
      currentWalletOwner = ethers.constants.AddressZero
    }
    
    // Initialize or update
    if (currentWalletOwner === ethers.constants.AddressZero) {
      console.log("\n=== Step 3: Initializing Wallet Owner (No Delay) ===")
      const initTx = await wrGovConnected.initializeWalletOwner(simpleWalletOwner.address)
      await initTx.wait()
      console.log("✓ Wallet Owner initialized! Transaction:", initTx.hash)
    } else {
      console.log("\n=== Step 3: Beginning Wallet Owner Update ===")
      const beginTx = await wrGovConnected.beginWalletOwnerUpdate(simpleWalletOwner.address)
      await beginTx.wait()
      console.log("✓ Update initiated! Transaction:", beginTx.hash)
      
      const changeInitiated = await wrGov.walletOwnerChangeInitiated()
      const governanceDelay = await wrGov.governanceDelay()
      const currentBlock = await ethers.provider.getBlock("latest")
      
      console.log("\n=== Step 4: Governance Delay Information ===")
      console.log("Change Initiated:", changeInitiated.toString())
      console.log("Current Timestamp:", currentBlock.timestamp.toString())
      console.log("Governance Delay:", governanceDelay.toString(), "seconds (", (governanceDelay.toNumber() / 86400).toFixed(2), "days)")
      
      const timeElapsed = currentBlock.timestamp - changeInitiated.toNumber()
      const delayPassed = timeElapsed >= governanceDelay.toNumber()
      
      console.log("Time Elapsed:", timeElapsed.toString(), "seconds")
      console.log("Delay Passed:", delayPassed)
      
      if (delayPassed) {
        console.log("\n=== Step 5: Finalizing Update ===")
        const finalizeTx = await wrGovConnected.finalizeWalletOwnerUpdate()
        await finalizeTx.wait()
        console.log("✓ Wallet Owner updated! Transaction:", finalizeTx.hash)
      } else {
        console.log("\n⚠️  Governance delay has not passed yet")
        console.log(`   Need to wait ${(governanceDelay.toNumber() - timeElapsed).toString()} more seconds`)
        console.log("\nTo advance time:")
        console.log("1. If geth is in Docker: Modify system time in container")
        console.log("2. Restart geth with faketime: faketime '7 days' geth ...")
        console.log("3. Wait for real time to pass")
        console.log("\nThen run:")
        console.log("  npx hardhat console --network development")
        console.log("  const { ethers, helpers } = require('hardhat');")
        console.log("  const wrGov = await helpers.contracts.getContract('WalletRegistryGovernance');")
        console.log("  const owner = await wrGov.owner();")
        console.log("  const signer = await ethers.getSigner(owner);")
        console.log("  await wrGov.connect(signer).finalizeWalletOwnerUpdate();")
        return
      }
    }
    
    // Verify
    console.log("\n=== Step 6: Verification ===")
    const newWalletOwner = await wr.walletOwner()
    console.log("New Wallet Owner:", newWalletOwner)
    
    const newCode = await ethers.provider.getCode(newWalletOwner)
    console.log("Is Contract:", newCode.length > 2)
    
    if (newCode.length > 2) {
      console.log("\n✅ SUCCESS! Wallet Owner is now a contract.")
      console.log("   You can now call approveDkgResult successfully!")
    } else {
      console.log("\n⚠️  Wallet Owner is still not a contract")
      console.log("   Something went wrong")
    }
    
  } catch (error: any) {
    console.error("\n❌ Error:", error.message)
    console.log("\nTroubleshooting:")
    console.log("1. Make sure geth node is running")
    console.log("2. Check that contracts are deployed")
    console.log("3. Verify you're using the correct network")
    process.exit(1)
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
