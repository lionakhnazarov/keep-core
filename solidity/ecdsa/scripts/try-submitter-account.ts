import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * Try calling approveDkgResult from the submitter's account
 */
async function main() {
  const WalletRegistry = await hre.deployments.get("WalletRegistry")
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address)

  // Get DKG result from event
  const filter = wr.filters.DkgResultSubmitted()
  const events = await wr.queryFilter(filter, -2000)
  if (events.length === 0) {
    console.error("No events found")
    process.exit(1)
  }

  const latestEvent = events[events.length - 1]
  const result = latestEvent.args.result
  
  // Get submitter operator address
  const sortitionPoolAddress = await wr.sortitionPool()
  const sortitionPoolABI = [
    "function getIDOperator(uint32 id) view returns (address)",
  ]
  const sp = new ethers.Contract(sortitionPoolAddress, sortitionPoolABI, ethers.provider)
  
  const submitterIndex = result.submitterMemberIndex
  const memberID = result.members[submitterIndex.sub(1).toNumber()]
  const submitterOperator = await sp.getIDOperator(memberID)
  
  console.log("==========================================")
  console.log("Trying approveDkgResult from Submitter Account")
  console.log("==========================================")
  console.log("")
  console.log(`Submitter operator: ${submitterOperator}`)
  console.log("")
  
  // Impersonate submitter account
  if (hre.network.name === "hardhat" || hre.network.name === "development") {
    console.log("Impersonating submitter account...")
    
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [submitterOperator],
    })
    
    // Fund the account if needed
    const balance = await ethers.provider.getBalance(submitterOperator)
    if (balance.lt(ethers.utils.parseEther("0.1"))) {
      const [deployer] = await ethers.getSigners()
      await deployer.sendTransaction({
        to: submitterOperator,
        value: ethers.utils.parseEther("1.0"),
      })
      console.log("Funded submitter account")
    }
    
    const submitterSigner = await ethers.getSigner(submitterOperator)
    const wrConnected = wr.connect(submitterSigner)
    
    console.log("Attempting approveDkgResult from submitter account...")
    console.log("")
    
    try {
      const tx = await wrConnected.approveDkgResult(result)
      console.log(`Transaction hash: ${tx.hash}`)
      const receipt = await tx.wait()
      console.log(`✅ SUCCESS! Block: ${receipt.blockNumber}`)
      console.log("")
      console.log("Wallet created successfully!")
      
      // Check for WalletCreated event
      const walletCreatedFilter = wr.filters.WalletCreated()
      const walletEvents = await wr.queryFilter(walletCreatedFilter, receipt.blockNumber, receipt.blockNumber)
      if (walletEvents.length > 0) {
        console.log(`Wallet ID: ${walletEvents[0].args.walletID}`)
      }
      
    } catch (error: any) {
      console.log("❌ Transaction failed:")
      console.log(`   Message: ${error.message}`)
      
      if (error.reason) {
        console.log(`   Reason: ${error.reason}`)
      }
      
      if (error.data && error.data !== "0x") {
        console.log(`   Data: ${error.data}`)
      }
    } finally {
      // Stop impersonating
      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [submitterOperator],
      })
    }
  } else {
    console.log("⚠️  Cannot impersonate accounts on this network")
    console.log(`   Please use account ${submitterOperator} to call approveDkgResult`)
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
