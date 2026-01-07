import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * Trace the approval transaction encoding to see what's actually being sent
 * Compare with the original submission transaction encoding
 */
async function main() {
  const WalletRegistry = await hre.deployments.get("WalletRegistry")
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address)

  // Get submission event
  const filter = wr.filters.DkgResultSubmitted()
  const currentBlock = await ethers.provider.getBlockNumber()
  const fromBlock = Math.max(0, currentBlock - 5000)
  const events = await wr.queryFilter(filter, fromBlock, currentBlock)
  
  if (events.length === 0) {
    console.error("Error: Could not find DKG result submission event")
    process.exit(1)
  }

  const latestEvent = events[events.length - 1]
  const eventResult = latestEvent.args.result
  const submissionTxHash = latestEvent.transactionHash
  
  console.log("==========================================")
  console.log("Trace Approval Encoding")
  console.log("==========================================")
  console.log("")
  console.log(`Submission TX: ${submissionTxHash}`)
  console.log(`Stored Hash: ${latestEvent.args.resultHash}`)
  console.log("")

  // Get original submission transaction
  const submissionTx = await ethers.provider.getTransaction(submissionTxHash)
  const submissionTxData = submissionTx.data
  
  console.log("Original submission transaction data:")
  console.log(`  Length: ${submissionTxData.length} chars`)
  console.log(`  Function selector: ${submissionTxData.slice(0, 10)}`)
  console.log(`  First 200 chars: ${submissionTxData.slice(0, 200)}...`)
  console.log("")

  // Encode the result for approval using Hardhat
  const [deployer] = await ethers.getSigners()
  const wrConnected = wr.connect(deployer)
  
  // Get the function interface
  const iface = wr.interface
  const approveFunction = iface.getFunction("approveDkgResult")
  
  // Encode the function call
  const encodedApproval = iface.encodeFunctionData("approveDkgResult", [eventResult])
  
  console.log("Approval transaction encoding:")
  console.log(`  Length: ${encodedApproval.length} chars`)
  console.log(`  Function selector: ${encodedApproval.slice(0, 10)}`)
  console.log(`  First 200 chars: ${encodedApproval.slice(0, 200)}...`)
  console.log("")

  // Compare function selectors
  const submissionSelector = submissionTxData.slice(0, 10)
  const approvalSelector = encodedApproval.slice(0, 10)
  
  console.log("Function selectors:")
  console.log(`  Submission: ${submissionSelector}`)
  console.log(`  Approval:   ${approvalSelector}`)
  console.log("")

  // Extract just the struct encoding (skip function selector)
  const submissionStructData = submissionTxData.slice(10)
  const approvalStructData = encodedApproval.slice(10)
  
  console.log("Struct encoding comparison:")
  console.log(`  Submission struct data length: ${submissionStructData.length}`)
  console.log(`  Approval struct data length:   ${approvalStructData.length}`)
  console.log("")

  if (submissionStructData === approvalStructData) {
    console.log("✅ Struct encodings match!")
  } else {
    console.log("❌ Struct encodings differ!")
    console.log("")
    console.log("First 200 chars of submission struct:")
    console.log(`  ${submissionStructData.slice(0, 200)}`)
    console.log("")
    console.log("First 200 chars of approval struct:")
    console.log(`  ${approvalStructData.slice(0, 200)}`)
    console.log("")
    
    // Find where they differ
    let diffPos = -1
    for (let i = 0; i < Math.min(submissionStructData.length, approvalStructData.length); i++) {
      if (submissionStructData[i] !== approvalStructData[i]) {
        diffPos = i
        break
      }
    }
    
    if (diffPos >= 0) {
      console.log(`First difference at position: ${diffPos}`)
      console.log(`  Submission: ${submissionStructData.slice(diffPos, diffPos + 20)}`)
      console.log(`  Approval:   ${approvalStructData.slice(diffPos, diffPos + 20)}`)
    }
  }

  // Compute hash from approval encoding
  const approvalStructBytes = ethers.utils.arrayify("0x" + approvalStructData)
  const approvalHash = ethers.utils.keccak256(approvalStructBytes)
  
  console.log("")
  console.log("Hash comparison:")
  console.log(`  Stored hash:  ${latestEvent.args.resultHash}`)
  console.log(`  Approval hash: ${approvalHash}`)
  
  if (approvalHash.toLowerCase() === latestEvent.args.resultHash.toLowerCase()) {
    console.log("✅ Hashes match!")
  } else {
    console.log("❌ Hashes don't match!")
    console.log("")
    console.log("This explains why approval fails - the encoding differs.")
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

