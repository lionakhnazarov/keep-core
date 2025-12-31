import type { HardhatRuntimeEnvironment } from "hardhat/types";
import type { DeployFunction } from "hardhat-deploy/types";
import { ZeroAddress } from "ethers";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { getNamedAccounts, deployments, ethers } = hre;
  const { deployer } = await getNamedAccounts();

  // Get deployed contract addresses
  let WalletRegistry: any = null;
  try {
    WalletRegistry = await deployments.get("WalletRegistry");
  } catch (e) {
    // Try to get from ecdsa deployments
  }

  if (!WalletRegistry) {
    // Try to get from ecdsa deployments
    try {
      const fs = require("fs");
      const path = require("path");
      const ecdsaPath = path.resolve(
        __dirname,
        "../../ecdsa/deployments/development/WalletRegistry.json"
      );
      if (fs.existsSync(ecdsaPath)) {
        const data = JSON.parse(fs.readFileSync(ecdsaPath, "utf8"));
        WalletRegistry = { address: data.address };
      }
    } catch (e) {
      throw new Error("WalletRegistry not found. Please deploy ECDSA contracts first.");
    }
  }

  let ReimbursementPool: any = null;
  try {
    ReimbursementPool = await deployments.get("ReimbursementPool");
  } catch (e) {
    // Will try file system lookup below
  }

  if (!ReimbursementPool) {
    try {
      const fs = require("fs");
      const path = require("path");
      const rbPath = path.resolve(
        __dirname,
        "../../random-beacon/deployments/development/ReimbursementPool.json"
      );
      if (fs.existsSync(rbPath)) {
        const data = JSON.parse(fs.readFileSync(rbPath, "utf8"));
        ReimbursementPool = { address: data.address };
      }
      } catch (e) {
        // Use zero address if not found
        ReimbursementPool = { address: ZeroAddress };
      }
  }

  // Helper function to deploy with stale file handling
  const deployWithStaleHandling = async (
    contractName: string,
    options: any
  ) => {
    // Check if contract already exists
    const existing = await deployments.getOrNull(contractName);
    if (existing) {
      // Verify contract exists on-chain
      const code = await hre.ethers.provider.getCode(existing.address);
      if (code && code.length > 2) {
        // Contract exists on-chain, reuse it
        deployments.log(`Reusing existing ${contractName} at ${existing.address}`);
        return existing;
      } else {
        // Contract doesn't exist on-chain, delete stale deployment
        deployments.log(
          `⚠️  ${contractName} deployment file exists but contract not found on-chain at ${existing.address}`
        );
        deployments.log(
          `   Deleting stale deployment file to allow fresh deployment...`
        );
        await deployments.delete(contractName);
      }
    }

    // Deploy contract
    try {
      return await deployments.deploy(contractName, options);
    } catch (error: any) {
      // If deployment fails due to missing transaction, delete stale deployment and retry
      const errorMessage = error.message || error.toString() || "";
      if (
        errorMessage.includes("cannot get the transaction") ||
        errorMessage.includes("transaction") ||
        errorMessage.includes("node synced status")
      ) {
        deployments.log(
          `⚠️  Error fetching previous deployment transaction for ${contractName}: ${errorMessage}`
        );
        deployments.log(`   Deleting stale deployment file and retrying...`);
        await deployments.delete(contractName);
        // Retry deployment
        return await deployments.deploy(contractName, options);
      } else {
        throw error;
      }
    }
  };

  // Check if Bridge exists and points to the correct WalletRegistry
  const existingBridge = await deployments.getOrNull("Bridge");
  let needsRedeploy = false;
  if (existingBridge && hre.network.name === "development") {
    try {
      const bridgeContract = await ethers.getContractAt(
        ["function contractReferences() view returns (address bank, address relay, address ecdsaWalletRegistry, address reimbursementPool)"],
        existingBridge.address
      );
      const refs = await bridgeContract.contractReferences();
      if (refs.ecdsaWalletRegistry.toLowerCase() !== WalletRegistry.address.toLowerCase()) {
        deployments.log(`⚠️  Bridge points to old WalletRegistry (${refs.ecdsaWalletRegistry}) but new one is at ${WalletRegistry.address}`);
        deployments.log(`   Redeploying Bridge to use new WalletRegistry...`);
        needsRedeploy = true;
        await deployments.delete("Bridge");
        await deployments.delete("BridgeStub");
      }
    } catch (e) {
      // If we can't check, assume we need to redeploy
      needsRedeploy = true;
    }
  }

  // Deploy Bridge stub
  const Bridge = await deployWithStaleHandling("BridgeStub", {
    contract: "BridgeStub",
    from: deployer,
    args: [
      ZeroAddress, // bank
      ZeroAddress, // relay
      WalletRegistry.address, // ecdsaWalletRegistry
      ReimbursementPool.address || ZeroAddress, // reimbursementPool
    ],
    log: true,
    waitConfirmations: 1,
  });

  // Save as Bridge for compatibility
  await deployments.save("Bridge", {
    address: Bridge.address,
    abi: Bridge.abi,
  });

  // Deploy MaintainerProxy stub
  const MaintainerProxy = await deployWithStaleHandling("MaintainerProxyStub", {
    contract: "MaintainerProxyStub",
    from: deployer,
    log: true,
    waitConfirmations: 1,
  });

  await deployments.save("MaintainerProxy", {
    address: MaintainerProxy.address,
    abi: MaintainerProxy.abi,
  });

  // Deploy WalletProposalValidator stub
  const WalletProposalValidator = await deployWithStaleHandling(
    "WalletProposalValidatorStub",
    {
      contract: "WalletProposalValidatorStub",
      from: deployer,
      log: true,
      waitConfirmations: 1,
    }
  );

  await deployments.save("WalletProposalValidator", {
    address: WalletProposalValidator.address,
    abi: WalletProposalValidator.abi,
  });

  console.log(`Bridge stub deployed at: ${Bridge.address}`);
  console.log(`MaintainerProxy stub deployed at: ${MaintainerProxy.address}`);
  console.log(
    `WalletProposalValidator stub deployed at: ${WalletProposalValidator.address}`
  );
};

export default func;
func.tags = ["TBTCStubs"];

