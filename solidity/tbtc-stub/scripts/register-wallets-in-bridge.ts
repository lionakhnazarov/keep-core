import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * Script to register wallets in Bridge that were created via DKG
 * but not automatically registered (because Bridge stub's callback is empty)
 * 
 * Usage: npx hardhat run scripts/register-wallets-in-bridge.ts --network development
 */

async function main() {
  const [deployer] = await ethers.getSigners()
  console.log("Deployer:", deployer.address)
  console.log("")

  // Get contract addresses
  // Bridge is in tbtc-stub, WalletRegistry is in ecdsa
  const Bridge = await hre.deployments.get("Bridge")
  
  // Get WalletRegistry from ecdsa deployments
  const fs = require("fs")
  const path = require("path")
  const walletRegistryPath = path.resolve(__dirname, "../../ecdsa/deployments/development/WalletRegistry.json")
  const walletRegistryDeployment = JSON.parse(fs.readFileSync(walletRegistryPath, "utf8"))
  const WalletRegistry = { address: walletRegistryDeployment.address }

  console.log("Bridge:", Bridge.address)
  console.log("WalletRegistry:", WalletRegistry.address)
  console.log("")

  // Get contract instances
  const bridge = await ethers.getContractAt("BridgeStub", Bridge.address)
  const wr = await ethers.getContractAt(
    [
      "function getWalletPublicKeyCoordinates(bytes32) view returns (bytes32, bytes32)",
      "function getWalletPublicKey(bytes32) view returns (bytes)",
      "function isWalletRegistered(bytes32) view returns (bool)",
      "event WalletCreated(bytes32 indexed walletID, bytes32 indexed dkgResultHash)",
    ],
    WalletRegistry.address
  )

  // Query WalletCreated events
  console.log("Querying WalletCreated events...")
  const filter = wr.filters.WalletCreated()
  const events = await wr.queryFilter(filter, 0, "latest")

  if (events.length === 0) {
    console.log("No WalletCreated events found.")
    return
  }

  console.log(`Found ${events.length} wallet(s)\n`)

  // Helper function to calculate walletPubKeyHash from public key coordinates
  // This matches the Go implementation: SHA256+RIPEMD160 of compressed public key
  function calculateWalletPubKeyHash(publicKeyX: string, publicKeyY: string): string {
    // Convert X and Y to BigInt
    const x = BigInt(publicKeyX)
    const y = BigInt(publicKeyY)

    // Determine if Y is even (for compressed format)
    const isYEven = y % 2n === 0n

    // Compressed public key format: 0x02 or 0x03 prefix + 32-byte X coordinate
    const prefix = isYEven ? 0x02 : 0x03
    const xBytes = ethers.zeroPadValue(ethers.toBeHex(x), 32)
    const compressedPubKey = ethers.concat([ethers.toBeHex(prefix), xBytes])

    // Apply SHA256 then RIPEMD160 (Hash160)
    const sha256Hash = ethers.sha256(compressedPubKey)
    const ripemd160Hash = ethers.ripemd160(sha256Hash)

    return ripemd160Hash
  }

  let registeredCount = 0
  let alreadyRegisteredCount = 0
  let errorCount = 0

  for (let i = 0; i < events.length; i++) {
    const event = events[i]
    const walletID = event.args[0] as string

    console.log(`[${i + 1}/${events.length}] Wallet ID: ${walletID}`)

    try {
      // Check if wallet is registered in WalletRegistry
      const isRegistered = await wr.isWalletRegistered(walletID)
      if (!isRegistered) {
        console.log("  ⚠️  Wallet not registered in WalletRegistry, skipping")
        console.log("")
        continue
      }

      // Get public key coordinates
      let publicKeyX: string
      let publicKeyY: string
      
      try {
        // Try getWalletPublicKeyCoordinates first (more direct)
        const coords = await wr.getWalletPublicKeyCoordinates(walletID)
        publicKeyX = coords[0] as string
        publicKeyY = coords[1] as string
      } catch (error: any) {
        // Fallback to getWalletPublicKey and parse bytes
        const publicKeyBytes = await wr.getWalletPublicKey(walletID)
        // Public key is 64 bytes: 32 bytes X + 32 bytes Y
        // Remove 0x prefix, then take first 64 chars (32 bytes) for X, next 64 for Y
        const hexWithoutPrefix = publicKeyBytes.replace("0x", "")
        publicKeyX = "0x" + hexWithoutPrefix.slice(0, 64) // First 64 hex chars = 32 bytes
        publicKeyY = "0x" + hexWithoutPrefix.slice(64, 128) // Next 64 hex chars = 32 bytes
      }
      
      // Ensure both are exactly 66 characters (0x + 64 hex chars)
      if (publicKeyX.length !== 66) {
        publicKeyX = ethers.zeroPadValue(publicKeyX, 32)
      }
      if (publicKeyY.length !== 66) {
        publicKeyY = ethers.zeroPadValue(publicKeyY, 32)
      }
      
      console.log(`  Public Key X: ${publicKeyX}`)
      console.log(`  Public Key Y: ${publicKeyY}`)

      // Calculate walletPubKeyHash
      const walletPubKeyHash = calculateWalletPubKeyHash(publicKeyX, publicKeyY)
      console.log(`  Wallet PubKey Hash: ${walletPubKeyHash}`)

      // Check if wallet is already registered in Bridge
      // Use cast call to check wallets mapping (state is uint32 at position 7)
      // Format: wallets(bytes20) returns (bytes32,bytes32,uint64,uint32,uint32,uint32,uint32,uint8,bytes32)
      // State is at index 7 (uint8)
      try {
        const provider = ethers.provider
        const walletsAbi = [
          "function wallets(bytes20) view returns (bytes32,bytes32,uint64,uint32,uint32,uint32,uint32,uint8,bytes32)"
        ]
        const bridgeContract = new ethers.Contract(Bridge.address, walletsAbi, provider)
        const walletData = await bridgeContract.wallets(walletPubKeyHash)
        const state = walletData[7] as number
        
        if (state !== 0) {
          const stateNames = ["Unknown", "Live", "MovingFunds", "Closing", "Closed", "Terminated"]
          console.log(`  ✓ Already registered in Bridge (state: ${state} = ${stateNames[state] || "Unknown"})`)
          alreadyRegisteredCount++
          continue
        }
      } catch (error: any) {
        // If call fails, wallet might not exist - try to register
        console.log(`  → Wallet not found in Bridge, registering...`)
      }

      console.log(`  → Registering wallet in Bridge...`)
      
      // Try static call first to check if it will succeed
      try {
        await bridge.registerWallet.staticCall(walletPubKeyHash, walletID)
      } catch (staticError: any) {
        console.log(`    ✗ Static call failed: ${staticError.message}`)
        if (staticError.data) {
          console.log(`    Data: ${staticError.data}`)
        }
        throw staticError
      }
      
      // Register wallet in Bridge
      const tx = await bridge.registerWallet(walletPubKeyHash, walletID)
      console.log(`    Transaction: ${tx.hash}`)
      
      await tx.wait()
      console.log(`  ✓ Successfully registered in Bridge`)
      registeredCount++
    } catch (error: any) {
      console.log(`  ✗ Error: ${error.message}`)
      if (error.data) {
        console.log(`    Data: ${error.data}`)
      }
      if (error.reason) {
        console.log(`    Reason: ${error.reason}`)
      }
      errorCount++
    }

    console.log("")
  }

  console.log("==========================================")
  console.log("Summary:")
  console.log(`  Total wallets: ${events.length}`)
  console.log(`  Newly registered: ${registeredCount}`)
  console.log(`  Already registered: ${alreadyRegisteredCount}`)
  console.log(`  Errors: ${errorCount}`)
  console.log("==========================================")
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
