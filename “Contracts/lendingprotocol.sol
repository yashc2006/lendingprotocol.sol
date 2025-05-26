// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title LendingProtocol
 * @dev Complete lending and borrowing protocol with interest calculations
 */
contract LendingProtocol is ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;

    // Constants
    uint256 public constant SCALE = 1e18;
    uint256 public constant SECONDS_PER_YEAR = 365 * 24 * 60 * 60;
    uint256 public constant LIQUIDATION_INCENTIVE = 1.08e18; // 8% bonus
    uint256 public constant CLOSE_FACTOR = 0.5e18; // Max 50% liquidation

    // Structs
    struct Asset {
        bool isActive;
        uint256 totalSupplied;
        uint256 totalBorrowed;
        uint256 supplyRatePerSecond;
        uint256 borrowRatePerSecond;
        uint256 reserveFactor; // Percentage to reserves (1e18 = 100%)
        uint256 collateralFactor; // Max borrow ratio (0.8e18 = 80%)
        uint256 liquidationThreshold; // Liquidation point (0.85e18 = 85%)
        uint256 lastUpdateTime;
        uint256 supplyIndex; // Accumulated supply interest
        uint256 borrowIndex; // Accumulated borrow interest
    }

    struct UserAssetData {
        uint256 suppliedAmount;
        uint256 borrowedAmount;
        uint256 supplyIndex;
        uint256 borrowIndex;
        bool isCollateral;
    }

    struct LiquidationData {
        uint256 totalCollateralValue;
        uint256 totalBorrowValue;
        uint256 healthFactor;
        bool canBeLiquidated;
    }

    // State variables
    mapping(address => Asset) public assets;
    mapping(address => mapping(address => UserAssetData)) public userData;
    mapping(address => address[]) public userAssets;
    mapping(address => uint256) public assetPrices; // Simplified oracle
    address[] public supportedAssets;

    // Events
    event AssetAdded(address indexed asset, uint256 supplyRate, uint256 borrowRate);
    event Supplied(address indexed user, address indexed asset, uint256 amount);
    event Withdrawn(address indexed user, address indexed asset, uint256 amount);
    event Borrowed(address indexed user, address indexed asset, uint256 amount);
    event Repaid(address indexed user, address indexed asset, uint256 amount);
    event CollateralToggled(address indexed user, address indexed asset, bool enabled);
    event Liquidated(
        address indexed liquidator,
        address indexed borrower,
        address indexed borrowAsset,
        address collateralAsset,
        uint256 repayAmount,
        uint256 seizeAmount
    );
    event InterestAccrued(address indexed asset, uint256 supplyIndex, uint256 borrowIndex);

    constructor() Ownable(msg.sender) {}

    // ============ ADMIN FUNCTIONS ============

    function addAsset(
        address _asset,
        uint256 _supplyRate, // Annual rate (1e18 = 100%)
        uint256 _borrowRate, // Annual rate (1e18 = 100%)
        uint256 _reserveFactor,
        uint256 _collateralFactor,
        uint256 _liquidationThreshold,
        uint256 _initialPrice
    ) external onlyOwner {
        require(!assets[_asset].isActive, "Asset already exists");
        require(_collateralFactor < _liquidationThreshold, "Invalid thresholds");
        require(_liquidationThreshold <= SCALE, "Threshold too high");

        assets[_asset] = Asset({
            isActive: true,
            totalSupplied: 0,
            totalBorrowed: 0,
            supplyRatePerSecond: _supplyRate / SECONDS_PER_YEAR,
            borrowRatePerSecond: _borrowRate / SECONDS_PER_YEAR,
            reserveFactor: _reserveFactor,
            collateralFactor: _collateralFactor,
            liquidationThreshold: _liquidationThreshold,
            lastUpdateTime: block.timestamp,
            supplyIndex: SCALE,
            borrowIndex: SCALE
        });

        assetPrices[_asset] = _initialPrice;
        supportedAssets.push(_asset);

        emit AssetAdded(_asset, _supplyRate, _borrowRate);
    }

    function updatePrice(address _asset, uint256 _price) external onlyOwner {
        require(assets[_asset].isActive, "Asset not supported");
        assetPrices[_asset] = _price;
    }

    // ============ INTEREST ACCRUAL ============

    function accrueInterest(address _asset) public {
        Asset storage asset = assets[_asset];
        require(asset.isActive, "Asset not active");

        uint256 currentTime = block.timestamp;
        uint256 deltaTime = currentTime - asset.lastUpdateTime;

        if (deltaTime == 0) return;

        uint256 borrowRate = asset.borrowRatePerSecond;
        uint256 supplyRate = asset.supplyRatePerSecond;

        // Calculate new indices
        if (asset.totalBorrowed > 0) {
            uint256 borrowInterest = (asset.totalBorrowed * borrowRate * deltaTime) / SCALE;
            asset.borrowIndex += (borrowInterest * SCALE) / asset.totalBorrowed;
        }

        if (asset.totalSupplied > 0) {
            uint256 supplyInterest = (asset.totalSupplied * supplyRate * deltaTime) / SCALE;
            asset.supplyIndex += (supplyInterest * SCALE) / asset.totalSupplied;
        }

        asset.lastUpdateTime = currentTime;
        emit InterestAccrued(_asset, asset.supplyIndex, asset.borrowIndex);
    }

    // ============ SUPPLY FUNCTIONS ============

    function supply(address _asset, uint256 _amount) external nonReentrant whenNotPaused {
        require(_amount > 0, "Amount must be > 0");
        require(assets[_asset].isActive, "Asset not supported");

        accrueInterest(_asset);
        
        UserAssetData storage user = userData[msg.sender][_asset];
        
        // Update user's accrued interest
        if (user.suppliedAmount > 0) {
            uint256 accruedInterest = (user.suppliedAmount * assets[_asset].supplyIndex) / user.supplyIndex - user.suppliedAmount;
            user.suppliedAmount += accruedInterest;
        }

        // Transfer tokens
        IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);

        // Update balances
        user.suppliedAmount += _amount;
        user.supplyIndex = assets[_asset].supplyIndex;
        assets[_asset].totalSupplied += _amount;

        // Add to user's asset list if first time
        if (!_isInArray(userAssets[msg.sender], _asset)) {
            userAssets[msg.sender].push(_asset);
        }

        emit Supplied(msg.sender, _asset, _amount);
    }

    function withdraw(address _asset, uint256 _amount) external nonReentrant whenNotPaused {
        require(_amount > 0, "Amount must be > 0");
        
        accrueInterest(_asset);
        
        UserAssetData storage user = userData[msg.sender][_asset];
        require(user.suppliedAmount >= _amount, "Insufficient balance");

        // Check if withdrawal would break collateral requirements
        if (user.isCollateral) {
            require(_canWithdraw(msg.sender, _asset, _amount), "Would break collateral requirements");
        }

        // Update user's accrued interest
        uint256 accruedInterest = (user.suppliedAmount * assets[_asset].supplyIndex) / user.supplyIndex - user.suppliedAmount;
        user.suppliedAmount += accruedInterest;

        // Update balances
        user.suppliedAmount -= _amount;
        user.supplyIndex = assets[_asset].supplyIndex;
        assets[_asset].totalSupplied -= _amount;

        // Transfer tokens
        IERC20(_asset).safeTransfer(msg.sender, _amount);

        emit Withdrawn(msg.sender, _asset, _amount);
    }

    // ============ BORROW FUNCTIONS ============

    function borrow(address _asset, uint256 _amount) external nonReentrant whenNotPaused {
        require(_amount > 0, "Amount must be > 0");
        require(assets[_asset].isActive, "Asset not supported");

        accrueInterest(_asset);

        // Check borrowing capacity
        require(_canBorrow(msg.sender, _asset, _amount), "Insufficient collateral");

        UserAssetData storage user = userData[msg.sender][_asset];

        // Update user's accrued interest
        if (user.borrowedAmount > 0) {
            uint256 accruedInterest = (user.borrowedAmount * assets[_asset].borrowIndex) / user.borrowIndex - user.borrowedAmount;
            user.borrowedAmount += accruedInterest;
        }

        // Update balances
        user.borrowedAmount += _amount;
        user.borrowIndex = assets[_asset].borrowIndex;
        assets[_asset].totalBorrowed += _amount;

        // Add to user's asset list if first time
        if (!_isInArray(userAssets[msg.sender], _asset)) {
            userAssets[msg.sender].push(_asset);
        }

        // Transfer tokens
        IERC20(_asset).safeTransfer(msg.sender, _amount);

        emit Borrowed(msg.sender, _asset, _amount);
    }

    function repay(address _asset, uint256 _amount) external nonReentrant whenNotPaused {
        require(_amount > 0, "Amount must be > 0");

        accrueInterest(_asset);

        UserAssetData storage user = userData[msg.sender][_asset];
        require(user.borrowedAmount > 0, "No debt to repay");

        // Update user's accrued interest
        uint256 accruedInterest = (user.borrowedAmount * assets[_asset].borrowIndex) / user.borrowIndex - user.borrowedAmount;
        user.borrowedAmount += accruedInterest;

        // Calculate actual repay amount
        uint256 repayAmount = _amount > user.borrowedAmount ? user.borrowedAmount : _amount;

        // Transfer tokens
        IERC20(_asset).safeTransferFrom(msg.sender, address(this), repayAmount);

        // Update balances
        user.borrowedAmount -= repayAmount;
        user.borrowIndex = assets[_asset].borrowIndex;
        assets[_asset].totalBorrowed -= repayAmount;

        emit Repaid(msg.sender, _asset, repayAmount);
    }

    // ============ COLLATERAL FUNCTIONS ============

    function enableCollateral(address _asset) external {
        require(assets[_asset].isActive, "Asset not supported");
        require(userData[msg.sender][_asset].suppliedAmount > 0, "No supply balance");
        
        userData[msg.sender][_asset].isCollateral = true;
        emit CollateralToggled(msg.sender, _asset, true);
    }

    function disableCollateral(address _asset) external {
        require(userData[msg.sender][_asset].isCollateral, "Not collateral");
        require(_canDisableCollateral(msg.sender, _asset), "Would break collateral requirements");
        
        userData[msg.sender][_asset].isCollateral = false;
        emit CollateralToggled(msg.sender, _asset, false);
    }

    // ============ LIQUIDATION FUNCTIONS ============

    function liquidate(
        address _borrower,
        address _borrowAsset,
        uint256 _repayAmount,
        address _collateralAsset
    ) external nonReentrant whenNotPaused {
        require(_borrower != msg.sender, "Cannot liquidate self");
        
        // Accrue interest for both assets
        accrueInterest(_borrowAsset);
        accrueInterest(_collateralAsset);

        // Check if borrower can be liquidated
        LiquidationData memory liquidation = _getLiquidationData(_borrower);
        require(liquidation.canBeLiquidated, "Account not liquidatable");

        UserAssetData storage borrowerBorrow = userData[_borrower][_borrowAsset];
        UserAssetData storage borrowerCollateral = userData[_borrower][_collateralAsset];
        
        require(borrowerBorrow.borrowedAmount > 0, "No borrow balance");
        require(borrowerCollateral.isCollateral && borrowerCollateral.suppliedAmount > 0, "No collateral");

        // Calculate maximum repay amount (close factor)
        uint256 maxRepay = (borrowerBorrow.borrowedAmount * CLOSE_FACTOR) / SCALE;
        uint256 actualRepay = _repayAmount > maxRepay ? maxRepay : _repayAmount;

        // Calculate collateral to seize
        uint256 seizeAmount = _calculateSeizeAmount(_borrowAsset, _collateralAsset, actualRepay);
        require(seizeAmount <= borrowerCollateral.suppliedAmount, "Insufficient collateral");

        // Perform liquidation
        IERC20(_borrowAsset).safeTransferFrom(msg.sender, address(this), actualRepay);

        // Update borrower's balances
        borrowerBorrow.borrowedAmount -= actualRepay;
        borrowerCollateral.suppliedAmount -= seizeAmount;
        
        // Update protocol balances
        assets[_borrowAsset].totalBorrowed -= actualRepay;
        assets[_collateralAsset].totalSupplied -= seizeAmount;

        // Transfer seized collateral to liquidator
        IERC20(_collateralAsset).safeTransfer(msg.sender, seizeAmount);

        emit Liquidated(msg.sender, _borrower, _borrowAsset, _collateralAsset, actualRepay, seizeAmount);
    }

    // ============ VIEW FUNCTIONS ============

    function getUserSupplyBalance(address _user, address _asset) external view returns (uint256) {
        UserAssetData memory user = userData[_user][_asset];
        if (user.suppliedAmount == 0) return 0;
        
        // Calculate with accrued interest
        uint256 currentIndex = _calculateCurrentSupplyIndex(_asset);
        return (user.suppliedAmount * currentIndex) / user.supplyIndex;
    }

    function getUserBorrowBalance(address _user, address _asset) external view returns (uint256) {
        UserAssetData memory user = userData[_user][_asset];
        if (user.borrowedAmount == 0) return 0;
        
        // Calculate with accrued interest
        uint256 currentIndex = _calculateCurrentBorrowIndex(_asset);
        return (user.borrowedAmount * currentIndex) / user.borrowIndex;
    }

    function getAccountLiquidity(address _user) external view returns (uint256 collateralValue, uint256 borrowValue, uint256 healthFactor) {
        LiquidationData memory data = _getLiquidationData(_user);
        return (data.totalCollateralValue, data.totalBorrowValue, data.healthFactor);
    }

    function getAssetInfo(address _asset) external view returns (
        uint256 totalSupplied,
        uint256 totalBorrowed,
        uint256 supplyRate,
        uint256 borrowRate,
        uint256 utilizationRate
    ) {
        Asset memory asset = assets[_asset];
        totalSupplied = asset.totalSupplied;
        totalBorrowed = asset.totalBorrowed;
        supplyRate = asset.supplyRatePerSecond * SECONDS_PER_YEAR;
        borrowRate = asset.borrowRatePerSecond * SECONDS_PER_YEAR;
        utilizationRate = totalSupplied > 0 ? (totalBorrowed * SCALE) / totalSupplied : 0;
    }

    // ============ INTERNAL FUNCTIONS ============

    function _canBorrow(address _user, address _asset, uint256 _amount) internal view returns (bool) {
        LiquidationData memory liquidation = _getLiquidationData(_user);
        uint256 borrowValue = (_amount * assetPrices[_asset]) / SCALE;
        return liquidation.totalCollateralValue >= liquidation.totalBorrowValue + borrowValue;
    }

    function _canWithdraw(address _user, address _asset, uint256 _amount) internal view returns (bool) {
        LiquidationData memory liquidation = _getLiquidationData(_user);
        uint256 collateralValue = (_amount * assetPrices[_asset] * assets[_asset].collateralFactor) / (SCALE * SCALE);
        return liquidation.totalCollateralValue - collateralValue >= liquidation.totalBorrowValue;
    }

    function _canDisableCollateral(address _user, address _asset) internal view returns (bool) {
        LiquidationData memory liquidation = _getLiquidationData(_user);
        UserAssetData memory user = userData[_user][_asset];
        uint256 collateralValue = (user.suppliedAmount * assetPrices[_asset] * assets[_asset].collateralFactor) / (SCALE * SCALE);
        return liquidation.totalCollateralValue - collateralValue >= liquidation.totalBorrowValue;
    }

    function _getLiquidationData(address _user) internal view returns (LiquidationData memory) {
        uint256 totalCollateralValue = 0;
        uint256 totalBorrowValue = 0;
        uint256 liquidationCollateralValue = 0;

        address[] memory userAssetList = userAssets[_user];
        
        for (uint256 i = 0; i < userAssetList.length; i++) {
            address asset = userAssetList[i];
            UserAssetData memory user = userData[_user][asset];
            uint256 price = assetPrices[asset];

            // Collateral calculation
            if (user.isCollateral && user.suppliedAmount > 0) {
                uint256 collateralValue = (user.suppliedAmount * price * assets[asset].collateralFactor) / (SCALE * SCALE);
                totalCollateralValue += collateralValue;
                
                uint256 liquidationValue = (user.suppliedAmount * price * assets[asset].liquidationThreshold) / (SCALE * SCALE);
                liquidationCollateralValue += liquidationValue;
            }

            // Borrow calculation
            if (user.borrowedAmount > 0) {
                totalBorrowValue += (user.borrowedAmount * price) / SCALE;
            }
        }

        uint256 healthFactor = totalBorrowValue > 0 ? (liquidationCollateralValue * SCALE) / totalBorrowValue : type(uint256).max;
        bool canBeLiquidated = healthFactor < SCALE;

        return LiquidationData({
            totalCollateralValue: totalCollateralValue,
            totalBorrowValue: totalBorrowValue,
            healthFactor: healthFactor,
            canBeLiquidated: canBeLiquidated
        });
    }

    function _calculateSeizeAmount(
        address _borrowAsset,
        address _collateralAsset,
        uint256 _repayAmount
    ) internal view returns (uint256) {
        uint256 borrowPrice = assetPrices[_borrowAsset];
        uint256 collateralPrice = assetPrices[_collateralAsset];
        
        // seizeAmount = repayAmount * borrowPrice * liquidationIncentive / collateralPrice
        return (_repayAmount * borrowPrice * LIQUIDATION_INCENTIVE) / (collateralPrice * SCALE);
    }

    function _calculateCurrentSupplyIndex(address _asset) internal view returns (uint256) {
        Asset memory asset = assets[_asset];
        uint256 deltaTime = block.timestamp - asset.lastUpdateTime;
        
        if (deltaTime == 0 || asset.totalSupplied == 0) {
            return asset.supplyIndex;
        }
        
        uint256 supplyInterest = (asset.totalSupplied * asset.supplyRatePerSecond * deltaTime) / SCALE;
        return asset.supplyIndex + (supplyInterest * SCALE) / asset.totalSupplied;
    }

    function _calculateCurrentBorrowIndex(address _asset) internal view returns (uint256) {
        Asset memory asset = assets[_asset];
        uint256 deltaTime = block.timestamp - asset.lastUpdateTime;
        
        if (deltaTime == 0 || asset.totalBorrowed == 0) {
            return asset.borrowIndex;
        }
        
        uint256 borrowInterest = (asset.totalBorrowed * asset.borrowRatePerSecond * deltaTime) / SCALE;
        return asset.borrowIndex + (borrowInterest * SCALE) / asset.totalBorrowed;
    }

    function _isInArray(address[] memory _array, address _element) internal pure returns (bool) {
        for (uint256 i = 0; i < _array.length; i++) {
            if (_array[i] == _element) {
                return true;
            }
        }
        return false;
    }

    // ============ EMERGENCY FUNCTIONS ============

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function emergencyWithdraw(address _asset, uint256 _amount) external onlyOwner {
        IERC20(_asset).safeTransfer(owner(), _amount);
    }
}
