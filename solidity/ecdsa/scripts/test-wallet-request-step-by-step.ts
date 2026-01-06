import { ethers } from "hardhat"
import hre from "hardhat"

async function main() {
  console.log("==========================================")
  console.log("Step-by-Step Wallet Request Test")
  console.log("==========================================")
  console.log("")

  // Get Bridge address
  const fs = require("fs")
  const path = require("path")
  const bridgePath = path.resolve(__dirname, "../../tbtc-stub/deployments/development/Bridge.json")
  
  let bridgeAddress: string
  if (fs.existsSync(bridgePath)) {
    const bridgeData = JSON.parse(fs.readFileSync(bridgePath, "utf8"))
    bridgeAddress = bridgeData.address
  } else {
    console.error("Error: Bridge deployment not found")
    process.exit(1)
  }

  // Get WalletRegistry
  const WalletRegistry = await hre.deployments.get("WalletRegistry")
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address)

  console.log(`Bridge: ${bridgeAddress}`)
  console.log(`WalletRegistry: ${WalletRegistry.address}`)
  console.log("")

  // Step 1: Check walletOwner
  console.log("Step 1: Checking walletOwner...")
  const walletOwner = await wr.walletOwner()
  console.log(`  walletOwner: ${walletOwner}`)
  if (walletOwner.toLowerCase() !== bridgeAddress.toLowerCase()) {
    console.error("  ✗ MISMATCH!")
    process.exit(1)
  }
  console.log("  ✓ Bridge is walletOwner")
  console.log("")

  // Step 2: Check DKG state
  console.log("Step 2: Checking DKG state...")
  const dkgState = await wr.getWalletCreationState()
  const stateNames = ["IDLE", "AWAITING_SEED", "AWAITING_RESULT", "CHALLENGE"]
  console.log(`  DKG State: ${stateNames[dkgState]} (${dkgState})`)
  if (dkgState !== 0) {
    console.error("  ✗ DKG is NOT in IDLE state!")
    process.exit(1)
  }
  console.log("  ✓ DKG is IDLE")
  console.log("")

  // Step 3: Check if sortition pool is locked
  console.log("Step 3: Checking sortition pool lock state...")
  try {
    const sortitionPoolAddress = await wr.sortitionPool()
    const SortitionPool = await ethers.getContractAt(
      ["function isLocked() view returns (bool)"],
      sortitionPoolAddress
    )
    const isLocked = await SortitionPool.isLocked()
    console.log(`  SortitionPool isLocked: ${isLocked}`)
    if (isLocked) {
      console.error("  ✗ SortitionPool is already locked!")
      console.error("  This will cause dkg.lockState() to revert")
      process.exit(1)
    }
    console.log("  ✓ SortitionPool is not locked")
  } catch (e: any) {
    console.log(`  ⚠ Could not check sortition pool: ${e.message}`)
  }
  console.log("")

  // Step 4: Check RandomBeacon
  console.log("Step 4: Checking RandomBeacon...")
  try {
    const randomBeaconAddress = await wr.randomBeacon()
    console.log(`  RandomBeacon: ${randomBeaconAddress}`)
    
    if (randomBeaconAddress === ethers.constants.AddressZero) {
      console.error("  ✗ RandomBeacon is not set!")
      process.exit(1)
    }

    // Check if WalletRegistry is authorized
    const RandomBeacon = await ethers.getContractAt(
      ["function isRequesterAuthorized(address) view returns (bool)"],
      randomBeaconAddress
    )
    const isAuthorized = await RandomBeacon.isRequesterAuthorized(WalletRegistry.address)
    console.log(`  WalletRegistry authorized: ${isAuthorized}`)
    if (!isAuthorized) {
      console.error("  ✗ WalletRegistry is NOT authorized in RandomBeacon!")
      console.error("  This will cause randomBeacon.requestRelayEntry() to revert")
      console.error("  Run: cd solidity/ecdsa && npx hardhat run scripts/authorize-wallet-registry-in-beacon.ts --network development")
      process.exit(1)
    }
    console.log("  ✓ WalletRegistry is authorized")
  } catch (e: any) {
    console.log(`  ⚠ Could not check RandomBeacon: ${e.message}`)
  }
  console.log("")

  // Step 5: Test calling Bridge.requestNewWallet() as Bridge
  console.log("Step 5: Testing Bridge.requestNewWallet() forwarding...")
  const Bridge = await ethers.getContractAt("BridgeStub", bridgeAddress)
  const bridgeEcdsaWalletRegistry = await Bridge.ecdsaWalletRegistry()
  console.log(`  Bridge.ecdsaWalletRegistry: ${bridgeEcdsaWalletRegistry}`)
  
  if (bridgeEcdsaWalletRegistry.toLowerCase() !== WalletRegistry.address.toLowerCase()) {
    console.error("  ✗ Bridge.ecdsaWalletRegistry doesn't match!")
    process.exit(1)
  }
  console.log("  ✓ Bridge.ecdsaWalletRegistry matches")
  console.log("")

  // Step 6: Try static call to see exact revert reason
  console.log("Step 6: Testing static call to Bridge.requestNewWallet()...")
  const [signer] = await ethers.getSigners()
  console.log(`  Using signer: ${signer.address}`)
  
  try {
    // Try calling WalletRegistry directly as Bridge (simulating what Bridge does)
    console.log("  Testing WalletRegistry.requestNewWallet() call from Bridge's perspective...")
    
    // We can't actually call as Bridge, but we can check if the call would work
    // by checking if Bridge has the right setup
    
    // Try static call to Bridge
    await Bridge.connect(signer).callStatic.requestNewWallet({ gasLimit: 500000 })
    console.log("  ✓ Static call succeeded!")
    console.log("")
    console.log("The call should work. Try sending transaction via Geth console:")
    console.log("")
    console.log("  geth attach http://localhost:8545")
    console.log("  personal.unlockAccount(eth.accounts[0], \"\", 0)")
    console.log(`  eth.sendTransaction({from: eth.accounts[0], to: "${bridgeAddress}", data: "0x72cc8c6d", gas: 500000})`)
    console.log("")
  } catch (error: any) {
    console.error("  ✗ Static call failed")
    console.error(`  Error: ${error.message}`)
    
    // Try to get more details
    if (error.data) {
      console.error(`  Error data: ${error.data}`)
    }
    
    // Check if it's a walletOwner issue
    if (error.message?.includes("Wallet Owner") || error.message?.includes("walletOwner")) {
      console.error("")
      console.error("  → Issue: msg.sender check failing")
      console.error("  This suggests Bridge is not forwarding the call correctly")
      console.error("  or WalletRegistry is not seeing Bridge as msg.sender")
    }
    
    // Check if it's a DKG state issue
    if (error.message?.includes("IDLE") || error.message?.includes("state")) {
      console.error("")
      console.error("  → Issue: DKG state check failing")
      console.error("  Even though we checked state is IDLE, the call sees different state")
      console.error("  This might be a timing issue or sortition pool lock issue")
    }
    
    // Check if it's a RandomBeacon issue
    if (error.message?.includes("RandomBeacon") || error.message?.includes("beacon")) {
      console.error("")
      console.error("  → Issue: RandomBeacon call failing")
      console.error("  WalletRegistry might not be authorized in RandomBeacon")
    }
    
    console.log("")
    console.log("Try using Geth console directly - it might work even if static call fails:")
    console.log("  geth attach http://localhost:8545")
    console.log(`  eth.sendTransaction({from: eth.accounts[0], to: "${bridgeAddress}", data: "0x72cc8c6d", gas: 500000})`)
    
    process.exit(1)
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

