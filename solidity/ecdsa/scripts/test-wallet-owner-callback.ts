import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * Test the WalletOwner callback directly to see if it reverts
 */
async function main() {
  const WalletRegistry = await hre.deployments.get("WalletRegistry")
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address)

  console.log("==========================================")
  console.log("Testing WalletOwner Callback Directly")
  console.log("==========================================")
  console.log(`WalletRegistry: ${WalletRegistry.address}`)
  console.log(`WalletOwner: ${await wr.walletOwner()}`)
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

  // Calculate walletID from groupPubKey
  const walletID = ethers.utils.keccak256(result.groupPubKey)
  const publicKeyX = ethers.utils.hexDataSlice(result.groupPubKey, 0, 32)
  const publicKeyY = ethers.utils.hexDataSlice(result.groupPubKey, 32, 64)
  
  console.log("Wallet Details:")
  console.log(`  WalletID: ${walletID}`)
  console.log(`  PublicKeyX: ${publicKeyX}`)
  console.log(`  PublicKeyY: ${publicKeyY}`)
  console.log("")

  // Get WalletOwner contract
  const walletOwnerAddress = await wr.walletOwner()
  console.log(`WalletOwner Address: ${walletOwnerAddress}`)
  
  // Try to get the contract interface
  let walletOwner
  try {
    // Try to load as IWalletOwner interface
    const IWalletOwner = await ethers.getContractAt("IWalletOwner", walletOwnerAddress)
    walletOwner = IWalletOwner
  } catch (e) {
    console.log("Could not load as IWalletOwner, trying direct call...")
    // Create a minimal interface
    const abi = [
      "function __ecdsaWalletCreatedCallback(bytes32,bytes32,bytes32) external"
    ]
    walletOwner = new ethers.Contract(walletOwnerAddress, abi, ethers.provider)
  }

  console.log("")
  console.log("=== Testing Callback ===")
  
  const [deployer] = await ethers.getSigners()
  
  // Test 1: Call directly from deployer (should fail if there's an access control check)
  console.log("Test 1: Calling callback directly from deployer...")
  try {
    const tx = await walletOwner.connect(deployer).populateTransaction.__ecdsaWalletCreatedCallback(
      walletID,
      publicKeyX,
      publicKeyY
    )
    
    // Use callStatic to simulate
    const result = await ethers.provider.call(tx)
    console.log("✅ Callback would succeed!")
    console.log(`   Result: ${result}`)
  } catch (error: any) {
    console.log("❌ Callback failed:")
    console.log(`   Message: ${error.message}`)
    if (error.data && error.data !== "0x") {
      console.log(`   Data: ${error.data}`)
    } else if (error.data === "0x") {
      console.log(`   Data: 0x (empty revert)`)
    }
  }

  console.log("")
  console.log("=== Testing Callback from WalletRegistry ===")
  
  // Test 2: Check if wallet already exists by trying to query it
  // Note: We can't directly check wallets mapping, but we can infer from events
  const walletCreatedEvents = await wr.queryFilter(
    wr.filters.WalletCreated(walletID),
    fromBlock
  )
  
  if (walletCreatedEvents.length > 0) {
    console.log("⚠️  Wallet already exists!")
    console.log(`   Created at block: ${walletCreatedEvents[0].blockNumber}`)
    console.log("")
    console.log("This might be why the callback is reverting - wallet already exists!")
  } else {
    console.log("✓ Wallet does not exist yet (expected)")
  }

  console.log("")
  console.log("=== Testing Full Approval Flow ===")
  
  // Test 3: Try the full approval but catch the error
  try {
    await wr.connect(deployer).callStatic.approveDkgResult(result)
    console.log("✅ Full approval would succeed!")
  } catch (error: any) {
    console.log("❌ Full approval failed:")
    console.log(`   Message: ${error.message}`)
    if (error.data && error.data !== "0x") {
      console.log(`   Data: ${error.data}`)
    } else if (error.data === "0x") {
      console.log(`   Data: 0x (empty revert)`)
    }
    
    // Check if it's an access control issue
    if (error.message.includes("onlyWalletOwner") || error.message.includes("Caller is not")) {
      console.log("")
      console.log("🔍 Likely cause: Access control check in WalletOwner callback")
    }
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
