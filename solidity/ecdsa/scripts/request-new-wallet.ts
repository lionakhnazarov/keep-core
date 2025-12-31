import { ethers } from "hardhat"
import hre from "hardhat"

async function main() {
  // Get Bridge address from deployments
  const fs = require("fs")
  const path = require("path")
  const bridgePath = path.resolve(__dirname, "../../tbtc-stub/deployments/development/Bridge.json")
  
  let bridgeAddress: string
  if (fs.existsSync(bridgePath)) {
    const bridgeData = JSON.parse(fs.readFileSync(bridgePath, "utf8"))
    bridgeAddress = bridgeData.address
  } else {
    console.error("Error: Bridge deployment not found at:", bridgePath)
    console.error("Please deploy Bridge first or provide Bridge address manually")
    process.exit(1)
  }
  
  console.log("==========================================")
  console.log("Requesting New Wallet (Triggering DKG)")
  console.log("==========================================")
  console.log("")
  console.log(`Bridge address: ${bridgeAddress}`)
  console.log("")
  
  // Verify walletOwner is set correctly
  const WalletRegistry = await hre.deployments.get("WalletRegistry")
  const wr = await ethers.getContractAt(
    ["function walletOwner() view returns (address)", "function requestNewWallet() external"],
    WalletRegistry.address
  )
  const walletOwner = await wr.walletOwner()
  console.log(`WalletRegistry walletOwner: ${walletOwner}`)
  
  if (walletOwner.toLowerCase() !== bridgeAddress.toLowerCase()) {
    console.error(`⚠️  ERROR: WalletOwner mismatch!`)
    console.error(`   Expected: ${bridgeAddress}`)
    console.error(`   Got: ${walletOwner}`)
    console.error(`   Please update walletOwner to match Bridge address`)
    console.error(`   Run: cd solidity/ecdsa && npx hardhat run scripts/init-wallet-owner.ts --network development`)
    process.exit(1)
  }
  
  console.log(`✓ WalletOwner matches Bridge`)
  console.log("")
  
  const [signer] = await ethers.getSigners()
  
  // Try to use Geth's impersonateAccount RPC method (for Geth nodes)
  console.log(`Attempting to impersonate Bridge account...`)
  let impersonated = false
  try {
    await hre.network.provider.send("eth_impersonateAccount", [bridgeAddress])
    impersonated = true
    console.log(`✓ Bridge account impersonated`)
  } catch (e: any) {
    console.log(`⚠️  Impersonation not available: ${e.message}`)
    console.log(`   Trying direct call via Bridge contract...`)
  }
  
  if (impersonated) {
    // Call WalletRegistry directly as Bridge (no gas needed when impersonated)
    const bridgeSigner = await ethers.getSigner(bridgeAddress)
    const wrWithBridge = wr.connect(bridgeSigner)
    
    console.log(`Calling WalletRegistry.requestNewWallet() as Bridge...`)
    try {
      const tx = await wrWithBridge.requestNewWallet({ gasLimit: 500000 })
      console.log(`Transaction submitted: ${tx.hash}`)
      const receipt = await tx.wait()
      console.log(`✓ DKG triggered successfully!`)
      console.log(`   Transaction confirmed in block: ${receipt.blockNumber}`)
      console.log(`   You can monitor DKG progress in node logs`)
      console.log("")
      console.log("==========================================")
      console.log("DKG Request Complete!")
      console.log("==========================================")
      
      // Stop impersonating
      try {
        await hre.network.provider.send("eth_stopImpersonatingAccount", [bridgeAddress])
      } catch (e) {
        // Ignore if not supported
      }
      return
    } catch (error: any) {
      console.error(`Error calling WalletRegistry: ${error.message}`)
      // Fall through to alternative methods
    }
  }
  
  // Alternative: Try calling Bridge.requestNewWallet() directly
  // This will work if Bridge contract has the function and can call WalletRegistry
  console.log(`Trying Bridge.requestNewWallet()...`)
  try {
    const bridge = await ethers.getContractAt(
      ["function requestNewWallet() external"],
      bridgeAddress
    )
    // Use explicit gas limit to avoid estimation issues
    const tx = await bridge.connect(signer).requestNewWallet({ 
      gasLimit: 500000,
      gasPrice: ethers.utils.parseUnits("1", "gwei")
    })
    console.log(`Transaction submitted: ${tx.hash}`)
    const receipt = await tx.wait()
    if (receipt.status === 1) {
      console.log(`✓ DKG triggered successfully!`)
      console.log(`   Transaction confirmed in block: ${receipt.blockNumber}`)
      console.log(`   You can monitor DKG progress in node logs`)
      console.log("")
      console.log("==========================================")
      console.log("DKG Request Complete!")
      console.log("==========================================")
      return
    } else {
      throw new Error("Transaction reverted")
    }
  } catch (error: any) {
    console.error(`Bridge contract call failed: ${error.message}`)
    if (error.message?.includes("gas")) {
      console.error(`   This may be a gas estimation issue. Try using cast or geth console.`)
    }
  }
  
  // If all else fails, provide manual instructions
  console.log("")
  console.log("⚠️  Automatic call failed. Bridge is a contract address, so we need a different approach.")
  console.log("")
  console.log("Solution: Call Bridge.requestNewWallet() from a regular account using cast:")
  console.log("   Bridge will forward the call to WalletRegistry, and WalletRegistry will see Bridge as the caller.")
  console.log("")
  console.log("Option 1: Using cast with unlocked account (recommended):")
  console.log(`   # First, unlock an account in Geth:`)
  console.log(`   geth attach http://localhost:8545`)
  console.log(`   > personal.unlockAccount(eth.accounts[0], "", 0)`)
  console.log(`   # Then use cast:`)
  console.log(`   cast send ${bridgeAddress} "requestNewWallet()" \\`)
  console.log(`     --rpc-url http://localhost:8545 \\`)
  console.log(`     --unlocked \\`)
  console.log(`     --from $(cast rpc eth_accounts --rpc-url http://localhost:8545 | jq -r '.[0]')`)
  console.log("")
  console.log("Option 2: Using cast with private key:")
  console.log(`   # Get an account with ETH from Geth:`)
  console.log(`   geth attach http://localhost:8545`)
  console.log(`   > eth.accounts[0]  # Use this address`)
  console.log(`   # Then use cast with the account's private key:`)
  console.log(`   cast send ${bridgeAddress} "requestNewWallet()" \\`)
  console.log(`     --rpc-url http://localhost:8545 \\`)
  console.log(`     --private-key <PRIVATE_KEY_OF_ACCOUNT_WITH_ETH>`)
  console.log("")
  console.log("Option 3: Using geth console directly:")
  console.log(`   geth attach http://localhost:8545`)
  console.log(`   > personal.unlockAccount(eth.accounts[0], "", 0)`)
  console.log(`   > eth.sendTransaction({from: eth.accounts[0], to: "${bridgeAddress}", data: "0x72cc8c6d", gas: 500000})`)
  console.log("")
  throw new Error("Failed to trigger DKG automatically. See instructions above.")
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
