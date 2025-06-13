const { ethers } = require("hardhat");

async function main() {
  console.log("Starting deployment...");

  // Get the deployer account
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);
  console.log("Account balance:", (await deployer.getBalance()).toString());

  // Deploy the LendingProtocol contract
  const LendingProtocol = await ethers.getContractFactory("LendingProtocol");
  console.log("Deploying LendingProtocol...");
  
  const lendingProtocol = await LendingProtocol.deploy();
  await lendingProtocol.deployed();

  console.log("LendingProtocol deployed to:", lendingProtocol.address);

  // Deploy mock ERC20 tokens for testing (optional)
  const MockERC20 = await ethers.getContractFactory("MockERC20");
  
  console.log("Deploying mock tokens...");
  
  // Deploy USDC mock
  const mockUSDC = await MockERC20.deploy(
    "Mock USDC",
    "mUSDC",
    18,
    ethers.utils.parseEther("1000000") // 1M tokens
  );
  await mockUSDC.deployed();
  console.log("Mock USDC deployed to:", mockUSDC.address);

  // Deploy DAI mock
  const mockDAI = await MockERC20.deploy(
    "Mock DAI",
    "mDAI",
    18,
    ethers.utils.parseEther("1000000") // 1M tokens
  );
  await mockDAI.deployed();
  console.log("Mock DAI deployed to:", mockDAI.address);

  // Deploy WETH mock
  const mockWETH = await MockERC20.deploy(
    "Mock WETH",
    "mWETH",
    18,
    ethers.utils.parseEther("10000") // 10K tokens
  );
  await mockWETH.deployed();
  console.log("Mock WETH deployed to:", mockWETH.address);

  // Create lending pools
  console.log("Creating lending pools...");

  // Create USDC pool (5% APR, 150% collateral ratio)
  await lendingProtocol.createPool(
    mockUSDC.address,
    500, // 5% APR (500 basis points)
    15000 // 150% collateral ratio (15000 basis points)
  );
  console.log("USDC pool created");

  // Create DAI pool (4% APR, 150% collateral ratio)
  await lendingProtocol.createPool(
    mockDAI.address,
    400, // 4% APR
    15000 // 150% collateral ratio
  );
  console.log("DAI pool created");

  // Create WETH pool (3% APR, 200% collateral ratio)
  await lendingProtocol.createPool(
    mockWETH.address,
    300, // 3% APR
    20000 // 200% collateral ratio
  );
  console.log("WETH pool created");

  // Distribute some tokens to the deployer for testing
  console.log("Distributing test tokens...");
  
  const testAmount = ethers.utils.parseEther("1000");
  await mockUSDC.transfer(deployer.address, testAmount);
  await mockDAI.transfer(deployer.address, testAmount);
  await mockWETH.transfer(deployer.address, ethers.utils.parseEther("10"));

  console.log("Deployment completed successfully!");
  console.log("\n=== Contract Addresses ===");
  console.log("LendingProtocol:", lendingProtocol.address);
  console.log("Mock USDC:", mockUSDC.address);
  console.log("Mock DAI:", mockDAI.address);
  console.log("Mock WETH:", mockWETH.address);

  console.log("\n=== Pool Information ===");
  console.log("USDC Pool: 5% APR, 150% collateral ratio");
  console.log("DAI Pool: 4% APR, 150% collateral ratio");
  console.log("WETH Pool: 3% APR, 200% collateral ratio");

  // Verify contracts on Etherscan (if on mainnet/testnet)
  if (network.name !== "hardhat" && network.name !== "localhost") {
    console.log("\n=== Verification ===");
    console.log("Waiting for block confirmations...");
    await lendingProtocol.deployTransaction.wait(5);
    
    try {
      await hre.run("verify:verify", {
        address: lendingProtocol.address,
        constructorArguments: [],
      });
      console.log("LendingProtocol verified on Etherscan");
    } catch (error) {
      console.log("Verification failed:", error.message);
    }
  }

  return {
    lendingProtocol: lendingProtocol.address,
    mockUSDC: mockUSDC.address,
    mockDAI: mockDAI.address,
    mockWETH: mockWETH.address
  };
}

// Handle deployment errors
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Deployment failed:", error);
    process.exit(1);
  });
