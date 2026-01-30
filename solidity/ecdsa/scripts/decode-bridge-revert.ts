import { ethers } from "hardhat"
import hre from "hardhat"

const TX_HASH = "0x1a3439d24816e3ebea08999a411264805169af53f06a3ca18db5b829082d42e3"
const BRIDGE_ADDRESS = "0x5a6A3B6c4A98BD2804bf65f96BdB7C1e179F2871"

async function main() {
  console.log("==========================================")
  console.log("Decoding Bridge Transaction Revert")
  console.log("==========================================")
  console.log("")
  console.log(`Transaction Hash: ${TX_HASH}`)
  console.log(`Bridge Address: ${BRIDGE_ADDRESS}`)
  console.log("")

  const provider = ethers.provider

  // Get transaction receipt
  const receipt = await provider.getTransactionReceipt(TX_HASH)
  if (!receipt) {
    console.error("❌ Transaction not found!")
    process.exit(1)
  }

  console.log(`Block Number: ${receipt.blockNumber}`)
  console.log(`Status: ${receipt.status === 1 ? "✅ Success" : "❌ Reverted"}`)
  console.log(`Gas Used: ${receipt.gasUsed.toString()}`)
  console.log("")

  if (receipt.status === 0) {
    console.log("Transaction reverted. Attempting to decode revert reason...")
    console.log("")

    // Get the transaction
    const tx = await provider.getTransaction(TX_HASH)
    if (!tx) {
      console.error("❌ Could not fetch transaction")
      process.exit(1)
    }

    console.log(`From: ${tx.from}`)
    console.log(`To: ${tx.to}`)
    console.log(`Data: ${tx.data}`)
    console.log("")

    // Try to decode the revert reason using a call
    try {
      // Replay the transaction as a call to get the revert reason
      const result = await provider.call({
        to: tx.to,
        from: tx.from,
        data: tx.data,
        gasLimit: tx.gasLimit,
        gasPrice: tx.gasPrice,
        value: tx.value,
      }, receipt.blockNumber - 1)

      console.log("Call result:", result)
    } catch (error: any) {
      console.log("Revert reason from call:")
      console.log(error.message)
      
      // Try to extract revert reason from error
      if (error.data) {
        console.log("Error data:", error.data)
        
        // Try to decode as a string
        try {
          const decoded = ethers.utils.defaultAbiCoder.decode(
            ["string"],
            error.data
          )
          console.log("Decoded revert reason:", decoded[0])
        } catch (e) {
          // Try to decode as Error(string)
          try {
            const decoded = ethers.utils.defaultAbiCoder.decode(
              ["string"],
              error.data.slice(10) // Remove 0x08c379a0 selector
            )
            console.log("Decoded Error(string):", decoded[0])
          } catch (e2) {
            console.log("Could not decode revert reason as string")
          }
        }
      }
    }

    // Check contract state
    console.log("")
    console.log("==========================================")
    console.log("Checking Contract State")
    console.log("==========================================")
    console.log("")

    // Get Bridge contract
    const Bridge = await ethers.getContractAt(
      [
        "function requestNewWallet() external",
        "function requestNewWallet((bytes32,uint32,uint64)) external",
        "function ecdsaWalletRegistry() view returns (address)",
      ],
      BRIDGE_ADDRESS
    )

    // Get WalletRegistry
    const WalletRegistry = await hre.deployments.get("WalletRegistry")
    const wr = await ethers.getContractAt(
      [
        "function walletOwner() view returns (address)",
        "function requestNewWallet() external",
        "function getWalletCreationState() view returns (uint8)",
        "function randomBeacon() view returns (address)",
      ],
      WalletRegistry.address
    )

    console.log(`WalletRegistry address: ${WalletRegistry.address}`)
    
    const walletOwner = await wr.walletOwner()
    console.log(`WalletRegistry.walletOwner(): ${walletOwner}`)
    console.log(`Bridge address: ${BRIDGE_ADDRESS}`)
    
    if (walletOwner.toLowerCase() !== BRIDGE_ADDRESS.toLowerCase()) {
      console.log("")
      console.log("⚠️  ISSUE FOUND: Bridge is not the walletOwner!")
      console.log(`   Expected walletOwner: ${BRIDGE_ADDRESS}`)
      console.log(`   Actual walletOwner: ${walletOwner}`)
      console.log("")
      console.log("   Fix: Update walletOwner to Bridge address")
      console.log("   Run: cd solidity/ecdsa && npx hardhat run scripts/init-wallet-owner.ts --network development")
    } else {
      console.log("✓ Bridge is the walletOwner")
    }

    // Check DKG state
    const dkgState = await wr.getWalletCreationState()
    const states = ["IDLE", "AWAITING_SEED", "AWAITING_RESULT", "CHALLENGE", "COMPLETE"]
    console.log("")
    console.log(`DKG State: ${dkgState} (${states[dkgState] || "UNKNOWN"})`)
    
    if (dkgState !== 0) {
      console.log("")
      console.log("⚠️  ISSUE FOUND: DKG is not in IDLE state!")
      console.log(`   Current state: ${states[dkgState] || "UNKNOWN"} (${dkgState})`)
      console.log("   DKG must be in IDLE state to request a new wallet")
    } else {
      console.log("✓ DKG is in IDLE state")
    }

    // Check RandomBeacon authorization
    const randomBeaconAddress = await wr.randomBeacon()
    console.log("")
    console.log(`RandomBeacon address: ${randomBeaconAddress}`)
    
    if (randomBeaconAddress !== ethers.constants.AddressZero) {
      const RandomBeacon = await ethers.getContractAt(
        [
          "function isRequesterAuthorized(address) view returns (bool)",
        ],
        randomBeaconAddress
      )
      
      const isAuthorized = await RandomBeacon.isRequesterAuthorized(WalletRegistry.address)
      console.log(`RandomBeacon.isRequesterAuthorized(${WalletRegistry.address}): ${isAuthorized}`)
      
      if (!isAuthorized) {
        console.log("")
        console.log("⚠️  ISSUE FOUND: WalletRegistry is not authorized in RandomBeacon!")
        console.log("   Fix: Authorize WalletRegistry in RandomBeacon")
        console.log("   Run: cd solidity/ecdsa && npx hardhat run scripts/authorize-wallet-registry-chaosnet.ts --network development")
      } else {
        console.log("✓ WalletRegistry is authorized in RandomBeacon")
      }
    }

    // Try to simulate the call
    console.log("")
    console.log("==========================================")
    console.log("Simulating requestNewWallet() Call")
    console.log("==========================================")
    console.log("")

    try {
      // Check if Bridge has requestNewWallet() with no params
      const bridgeCode = await provider.getCode(BRIDGE_ADDRESS)
      console.log(`Bridge code length: ${bridgeCode.length} bytes`)
      
      // Try calling requestNewWallet() with no params
      try {
        await Bridge.callStatic.requestNewWallet({ gasLimit: 500000 })
        console.log("✓ Bridge.requestNewWallet() call would succeed")
      } catch (error: any) {
        console.log("❌ Bridge.requestNewWallet() call failed:")
        console.log(`   ${error.message}`)
        
        // Try with struct parameter
        try {
          const NO_MAIN_UTXO = {
            txHash: ethers.constants.HashZero,
            outputIndex: 0,
            amount: 0,
          }
          await Bridge.callStatic["requestNewWallet((bytes32,uint32,uint64))"](NO_MAIN_UTXO, { gasLimit: 500000 })
          console.log("✓ Bridge.requestNewWallet(struct) call would succeed")
        } catch (error2: any) {
          console.log("❌ Bridge.requestNewWallet(struct) call also failed:")
          console.log(`   ${error2.message}`)
        }
      }
    } catch (error: any) {
      console.log("Could not simulate call:", error.message)
    }
  }

  console.log("")
  console.log("==========================================")
  console.log("Done")
  console.log("==========================================")
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
