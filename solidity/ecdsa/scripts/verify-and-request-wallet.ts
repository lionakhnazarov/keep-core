import { ethers } from "hardhat"
import hre from "hardhat"

async function main() {
  console.log("==========================================")
  console.log("Verify Setup and Request Wallet")
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

  console.log(`Bridge address: ${bridgeAddress}`)
  console.log(`WalletRegistry address: ${WalletRegistry.address}`)
  console.log("")

  // Check walletOwner
  console.log("Checking walletOwner...")
  const walletOwner = await wr.walletOwner()
  console.log(`Current walletOwner: ${walletOwner}`)
  console.log(`Expected walletOwner: ${bridgeAddress}`)
  
  if (walletOwner.toLowerCase() !== bridgeAddress.toLowerCase()) {
    console.error("✗ ERROR: walletOwner mismatch!")
    console.error("Run: cd solidity/ecdsa && npx hardhat run scripts/init-wallet-owner.ts --network development")
    process.exit(1)
  }
  console.log("✓ walletOwner is correct")
  console.log("")

  // Check DKG state
  console.log("Checking DKG state...")
  const dkgState = await wr.getWalletCreationState()
  const stateNames = ["IDLE", "AWAITING_SEED", "AWAITING_RESULT", "CHALLENGE"]
  const stateName = stateNames[dkgState] || `UNKNOWN(${dkgState})`
  console.log(`DKG State: ${stateName} (${dkgState})`)
  
  if (dkgState !== 0) {
    console.error("✗ ERROR: DKG is not in IDLE state!")
    process.exit(1)
  }
  console.log("✓ DKG is in IDLE state")
  console.log("")

  // Check Bridge's ecdsaWalletRegistry
  console.log("Checking Bridge configuration...")
  const Bridge = await ethers.getContractAt("BridgeStub", bridgeAddress)
  const bridgeEcdsaWalletRegistry = await Bridge.ecdsaWalletRegistry()
  console.log(`Bridge.ecdsaWalletRegistry: ${bridgeEcdsaWalletRegistry}`)
  console.log(`WalletRegistry address: ${WalletRegistry.address}`)
  
  if (bridgeEcdsaWalletRegistry.toLowerCase() !== WalletRegistry.address.toLowerCase()) {
    console.error("✗ ERROR: Bridge.ecdsaWalletRegistry doesn't match WalletRegistry!")
    console.error("Bridge needs to be redeployed or updated")
    process.exit(1)
  }
  console.log("✓ Bridge.ecdsaWalletRegistry matches WalletRegistry")
  console.log("")

  // Try calling Bridge.requestNewWallet() directly
  console.log("Attempting to call Bridge.requestNewWallet()...")
  const [signer] = await ethers.getSigners()
  console.log(`Using signer: ${signer.address}`)
  
  try {
    // First try a static call to see if it will work
    console.log("Testing with static call...")
    await Bridge.connect(signer).callStatic.requestNewWallet({ gasLimit: 500000 })
    console.log("✓ Static call succeeded")
    
    // If static call works, send actual transaction
    console.log("Sending transaction...")
    const tx = await Bridge.connect(signer).requestNewWallet({ 
      gasLimit: 500000,
      gasPrice: ethers.utils.parseUnits("1", "gwei")
    })
    console.log(`Transaction hash: ${tx.hash}`)
    
    console.log("Waiting for confirmation...")
    const receipt = await tx.wait()
    
    if (receipt.status === 1) {
      console.log("✓ Transaction succeeded!")
      console.log(`Block: ${receipt.blockNumber}`)
      console.log("DKG has been triggered!")
      return
    } else {
      throw new Error("Transaction reverted")
    }
  } catch (error: any) {
    console.error("✗ Transaction failed")
    console.error(`Error: ${error.message}`)
    
    // Try to decode error
    if (error.data) {
      console.error(`Error data: ${error.data}`)
    }
    
    console.log("")
    console.log("==========================================")
    console.log("Fallback: Direct WalletRegistry Call")
    console.log("==========================================")
    console.log("")
    console.log("Since Bridge forwarding isn't working, try calling")
    console.log("WalletRegistry directly using Hardhat's impersonation:")
    console.log("")
    console.log("This requires modifying the script to use")
    console.log("hardhat_impersonateAccount (Hardhat Network only)")
    console.log("")
    console.log("For Geth, use geth console:")
    console.log("  geth attach http://localhost:8545")
    console.log("  personal.unlockAccount(eth.accounts[0], \"\", 0)")
    console.log(`  eth.sendTransaction({from: eth.accounts[0], to: "${bridgeAddress}", data: "0x72cc8c6d", gas: 500000})`)
    console.log("")
    
    process.exit(1)
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

