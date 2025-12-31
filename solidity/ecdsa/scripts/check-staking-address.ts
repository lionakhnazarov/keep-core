import { HardhatRuntimeEnvironment } from "hardhat/types"

async function main() {
  const hre: HardhatRuntimeEnvironment = require("hardhat")
  const { helpers } = hre
  
  console.log("=== Checking Staking Addresses ===")
  console.log("")
  
  const wr = await helpers.contracts.getContract("WalletRegistry")
  const wrStaking = await wr.staking()
  console.log("WalletRegistry.staking():", wrStaking)
  
  const extendedTS = await helpers.contracts.getContract("ExtendedTokenStaking")
  console.log("ExtendedTokenStaking address:", extendedTS.address)
  
  const tokenStaking = await helpers.contracts.getContract("TokenStaking")
  console.log("TokenStaking address:", tokenStaking.address)
  
  console.log("")
  console.log("Match ExtendedTokenStaking:", wrStaking.toLowerCase() === extendedTS.address.toLowerCase())
  console.log("Match TokenStaking:", wrStaking.toLowerCase() === tokenStaking.address.toLowerCase())
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
