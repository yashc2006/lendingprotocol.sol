# Decentralized Lending Protocol

A comprehensive DeFi lending protocol built with Solidity that enables users to lend and borrow ERC20 tokens with automated interest calculations, collateral management, and liquidation mechanisms.

## 🚀 Features

### Core Functionality
- **Supply & Earn**: Deposit tokens to earn continuous compound interest
- **Borrow**: Take loans against your collateral with competitive rates
- **Multi-Asset Support**: Support for any ERC20 token with custom parameters
- **Real-time Interest**: Per-second compound interest calculations
- **Collateral Management**: Flexible collateral enabling/disabling
- **Automated Liquidations**: Protect the protocol from bad debt

### Advanced Features
- **Health Factor Monitoring**: Real-time solvency tracking
- **Liquidation Incentives**: 8% bonus for liquidators
- **Reserve System**: Protocol fee collection for sustainability
- **Emergency Controls**: Pause functionality and admin controls
- **Gas Optimized**: Efficient storage and calculation patterns

## 📋 Prerequisites

- Solidity ^0.8.19
- OpenZeppelin Contracts v4.9.0+
- Hardhat or Foundry for development
- Node.js v16+ for deployment scripts

## 🛠 Installation

```bash
# Clone the repository
git clone <repository-url>
cd lending-protocol

# Install dependencies
npm install

# Install OpenZeppelin contracts
npm install @openzeppelin/contracts
```

## 📖 Contract Architecture

### Core Contracts
- `LendingProtocol.sol` - Main protocol contract
- Uses OpenZeppelin's `ReentrancyGuard`, `Ownable`, and `Pausable`

### Key Data Structures

```solidity
struct Asset {
    bool isActive;
    uint256 totalSupplied;
    uint256 totalBorrowed;
    uint256 supplyRatePerSecond;
    uint256 borrowRatePerSecond;
    uint256 reserveFactor;
    uint256 collateralFactor;
    uint256 liquidationThreshold;
    uint256 lastUpdateTime;
    uint256 supplyIndex;
    uint256 borrowIndex;
}

struct UserAssetData {
    uint256 suppliedAmount;
    uint256 borrowedAmount;
    uint256 supplyIndex;
    uint256 borrowIndex;
    bool isCollateral;
}
```

## 🚦 Getting Started

### 1. Deploy the Contract

```javascript
// Using Hardhat
const LendingProtocol = await ethers.getContractFactory("LendingProtocol");
const lending = await LendingProtocol.deploy();
await lending.deployed();
```

### 2. Add Supported Assets

```javascript
// Add USDC with 5% supply rate, 8% borrow rate
await lending.addAsset(
    USDC_ADDRESS,
    "50000000000000000",  // 5% annual supply rate
    "80000000000000000",  // 8% annual borrow rate
    "100000000000000000", // 10% reserve factor
    "800000000000000000", // 80% collateral factor
    "850000000000000000", // 85% liquidation threshold
    "1000000000000000000" // $1 initial price
);
```

### 3. Basic Usage Flow

```javascript
// 1. Supply tokens to earn interest
await usdcToken.approve(lending.address, amount);
await lending.supply(USDC_ADDRESS, amount);

// 2. Enable asset as collateral
await lending.enableCollateral(USDC_ADDRESS);

// 3. Borrow against collateral
await lending.borrow(DAI_ADDRESS, borrowAmount);

// 4. Repay loan
await daiToken.approve(lending.address, repayAmount);
await lending.repay(DAI_ADDRESS, repayAmount);

// 5. Withdraw supplied tokens
await lending.withdraw(USDC_ADDRESS, withdrawAmount);
```

## 📊 Key Parameters

### Interest Rates
- **Supply Rate**: Annual percentage yield for lenders
- **Borrow Rate**: Annual percentage rate for borrowers
- **Reserve Factor**: Percentage of interest going to protocol reserves

### Risk Parameters
- **Collateral Factor**: Maximum borrowing power (e.g., 80% = borrow up to 80% of collateral value)
- **Liquidation Threshold**: Point where liquidation becomes possible (e.g., 85%)
- **Liquidation Incentive**: Bonus for liquidators (8%)
- **Close Factor**: Maximum debt liquidatable at once (50%)

## 🔍 Contract Functions

### User Functions

#### Supply Operations
```solidity
function supply(address _asset, uint256 _amount) external
function withdraw(address _asset, uint256 _amount) external
```

#### Borrow Operations
```solidity
function borrow(address _asset, uint256 _amount) external
function repay(address _asset, uint256 _amount) external
```

#### Collateral Management
```solidity
function enableCollateral(address _asset) external
function disableCollateral(address _asset) external
```

#### Liquidation
```solidity
function liquidate(
    address _borrower,
    address _borrowAsset,
    uint256 _repayAmount,
    address _collateralAsset
) external
```

### View Functions

#### User Information
```solidity
function getUserSupplyBalance(address _user, address _asset) external view returns (uint256)
function getUserBorrowBalance(address _user, address _asset) external view returns (uint256)
function getAccountLiquidity(address _user) external view returns (uint256, uint256, uint256)
```

#### Market Information
```solidity
function getAssetInfo(address _asset) external view returns (uint256, uint256, uint256, uint256, uint256)
```

### Admin Functions

```solidity
function addAsset(...) external onlyOwner
function updatePrice(address _asset, uint256 _price) external onlyOwner
function pause() external onlyOwner
function unpause() external onlyOwner
```

## 💡 Usage Examples

### Example 1: Basic Lending
```javascript
// Supply 1000 USDC
await usdc.approve(lending.address, ethers.utils.parseUnits("1000", 6));
await lending.supply(usdc.address, ethers.utils.parseUnits("1000", 6));

// Check earned interest after some time
const balance = await lending.getUserSupplyBalance(user.address, usdc.address);
console.log("Balance with interest:", ethers.utils.formatUnits(balance, 6));
```

### Example 2: Borrowing Flow
```javascript
// 1. Supply collateral
await usdc.approve(lending.address, ethers.utils.parseUnits("1000", 6));
await lending.supply(usdc.address, ethers.utils.parseUnits("1000", 6));

// 2. Enable as collateral
await lending.enableCollateral(usdc.address);

// 3. Check borrowing capacity
const [collateralValue, borrowValue, healthFactor] = await lending.getAccountLiquidity(user.address);

// 4. Borrow DAI (up to 80% of collateral value)
await lending.borrow(dai.address, ethers.utils.parseUnits("500", 18));
```

### Example 3: Liquidation
```javascript
// Check if user can be liquidated
const [, , healthFactor] = await lending.getAccountLiquidity(borrower.address);

if (healthFactor < ethers.utils.parseEther("1")) {
    // Perform liquidation
    await dai.approve(lending.address, repayAmount);
    await lending.liquidate(
        borrower.address,
        dai.address,
        repayAmount,
        usdc.address
    );
}
```

## 🔐 Security Features

### Access Control
- **Owner-only functions**: Asset management, price updates, emergency controls
- **User isolation**: Each user's data is completely separate
- **Permission validation**: All operations check user permissions

### Attack Prevention
- **Reentrancy Protection**: `nonReentrant` modifier on all state-changing functions
- **Integer Overflow Protection**: Solidity 0.8+ built-in overflow checks
- **Input Validation**: Comprehensive parameter validation
- **Emergency Pause**: Admin can pause all operations if needed

### Economic Security
- **Health Factor Monitoring**: Prevents undercollateralized positions
- **Liquidation Incentives**: Encourages timely liquidations
- **Reserve System**: Protocol collects fees for sustainability
- **Interest Rate Models**: Balanced rates for supply and demand

## 📈 Interest Calculation

Interest is calculated using compound interest formula applied per second:

```
New Balance = Principal × (1 + Rate)^Time
```

Where:
- Rate = Annual Rate ÷ Seconds Per Year
- Time = Seconds elapsed since last update

## 🚨 Risk Management

### For Users
- **Diversify Collateral**: Don't put all eggs in one basket
- **Monitor Health Factor**: Keep it well above 1.0
- **Understand Liquidation Risk**: Know your liquidation threshold
- **Check Interest Rates**: Rates can change based on utilization

### For Protocol
- **Conservative Parameters**: Safe collateral factors and liquidation thresholds
- **Oracle Reliability**: Accurate price feeds are crucial
- **Emergency Controls**: Pause functionality for crisis management
- **Regular Audits**: Code should be audited before mainnet deployment

## 🧪 Testing

```bash
# Run all tests
npx hardhat test

# Run specific test file
npx hardhat test test/LendingProtocol.test.js

# Check test coverage
npx hardhat coverage
```

### Test Scenarios
- Basic supply and withdraw operations
- Borrow and repay functionality
- Interest accrual calculations
- Collateral management
- Liquidation mechanics
- Edge cases and error conditions

## 📦 Deployment

### Local Development
```bash
# Start local blockchain
npx hardhat node

# Deploy to local network
npx hardhat run scripts/deploy.js --network localhost
```

### Testnet Deployment
```bash
# Deploy to Goerli
npx hardhat run scripts/deploy.js --network goerli

# Verify contract
npx hardhat verify --network goerli DEPLOYED_CONTRACT_ADDRESS
```

### Mainnet Considerations
- Conduct thorough security audit
- Start with conservative parameters
- Have emergency response plan
- Monitor protocol health closely

## 🔧 Configuration

### Environment Variables
```bash
# .env file
PRIVATE_KEY=your_private_key
INFURA_API_KEY=your_infura_key
ETHERSCAN_API_KEY=your_etherscan_key
```

### Network Configuration
```javascript
// hardhat.config.js
networks: {
  goerli: {
    url: `https://goerli.infura.io/v3/${process.env.INFURA_API_KEY}`,
    accounts: [process.env.PRIVATE_KEY]
  }
}
```

## 📚 Additional Resources

- [OpenZeppelin Documentation](https://docs.openzeppelin.com/)
- [Solidity Documentation](https://docs.soliditylang.org/)
- [Hardhat Documentation](https://hardhat.org/docs)
- [DeFi Security Best Practices](https://consensys.github.io/smart-contract-best-practices/)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ⚠️ Disclaimer

This code is provided for educational purposes and has not been audited. Do not use in production without proper security auditing and testing. DeFi protocols involve significant financial risks.

## 📞 Support

For questions and support:
- Create an issue in the GitHub repository
- Join our Discord community
- Check the documentation wiki

---

**Built with ❤️ for the DeFi community**!
[Screenshot 2025-05-26 130828](https://github.com/user-attachments/assets/38c35eac-e17b-4e00-9158-7d5ca2c22d9c)
