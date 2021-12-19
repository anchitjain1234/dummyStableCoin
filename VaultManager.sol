// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./Base.sol";

import "./SortedVaults.sol";
import "./PriceFeed.sol";
import "./LiquidityMath.sol";
import "./StabilityPool.sol";
import "./ActivePool.sol";
import "./GasPool.sol";
import "./LUSDToken.sol";


import "hardhat/console.sol";

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";


contract VaultManager is Base, Ownable {
    SortedVaults public sortedVaults;
    PriceFeed public priceFeed;
    StabilityPool public stabilityPool;
    ActivePool public activePool;
    LUSDToken public lusdToken;
    GasPool public gasPool;

    uint256 public baseRate;

    address public borrowingAddress;

    enum Status {
        nonExistent,
        active,
        closedByOwner,
        closedByLiquidation,
        closedByRedemption
    }

    struct Vault {
        uint256 debt;
        uint256 collateral;
        Status status;
    }

    mapping(address => Vault) public vaults;

    constructor() {
        sortedVaults = new SortedVaults(msg.sender);
        borrowingAddress = msg.sender;
        baseRate = 0;
    }

    function setAddresses(address _priceFeedAddress, address _stabilityPoolAddress, ActivePool _activePool, LUSDToken _lusdToken, GasPool _gasPool) external onlyOwner {
        priceFeed = PriceFeed(_priceFeedAddress);
        stabilityPool = StabilityPool(_stabilityPoolAddress);
        activePool = _activePool;
        lusdToken = _lusdToken;
        gasPool = _gasPool;

        renounceOwnership();
    }

    //collateral ratio without price
    function getNominalICR(address _borrower) public view returns(uint256) {
        // collateral / debt
        (uint256 currentETH, uint256 currentLUSDDebt) = _getCurrentVaultAmounts(_borrower);
        if (currentLUSDDebt > 0) {
            return currentETH * DECIMAL_PRECISION / currentLUSDDebt;
        } else {
            return 2**256 - 1;
        }
    }

    function getBorrowingFee(uint256 _lusdAmount) external view returns(uint256) {
        //base rate + 0.5 of LUSD amt
        return baseRate + BORROWING_FEE_FLOOR * _lusdAmount / DECIMAL_PRECISION;
    }

    function createVault(address _borrower, uint256 _ethAmount, uint256 _debt) external onlyBorrowingContract {
        vaults[_borrower].status = Status.active;
        vaults[_borrower].collateral = _ethAmount;
        vaults[_borrower].debt = _debt;

        sortedVaults.insert(_borrower, getNominalICR(_borrower));
    }

    function getVaultCollateral(address _borrower) external view returns(uint256) {
        return vaults[_borrower].collateral;
    }

    function getVaultDebt(address _borrower) external view returns(uint256) {
        return vaults[_borrower].debt;
    }

    function closeVault(address _borrower) external onlyBorrowingContract {
        _closeVault(_borrower, Status.closedByOwner);
    }

    function liquidate(address _borrower) external {
        // get the price of the collateral
        uint256 price = priceFeed.getPrice();
        console.log("Price %s", price);

        // get Vault info
        (uint256 currentETH, uint256 currentLUSDDebt) = _getCurrentVaultAmounts(_borrower);
        console.log("currentETH %s, currentLUSDDebt %s", currentETH, currentLUSDDebt);

        // verify collateral ratio is less than needed
        uint256 collateralRatio = LiquidityMath._computeCR(currentETH, currentLUSDDebt, price);
        console.log("collateralRatio %s", collateralRatio);
        require(collateralRatio < MINIMUM_COLLATERAL_RATIO, "VaultManager: Cannot liquidate vault");

        // verify enough LUSD in Stability pool
        uint256 lusdInStabilityPool = stabilityPool.getTotalLUSDDeposits();
        require(lusdInStabilityPool >= currentLUSDDebt, "VaultManager: Insufficient funds in stability pool");

        // calculate collateral compensation
        uint256 collateralCompensation = currentETH * LIQUIDATOR_FEE_PERCENT_DIVISOR;
        uint256 collateralToLiquidate = currentETH - collateralCompensation;

        // decrease LUSD debt from active pool
        activePool.decreaseLUSDDebt(currentLUSDDebt);

        // close vault
        _closeVault(_borrower, Status.closedByLiquidation);

        // update LUSD deposits in the stability pool and burn tokens -> offset
        stabilityPool.offSet(currentLUSDDebt);

        // send liquidated ETH to stability pool -> distributed among providers
        activePool.sendETH(address(stabilityPool), collateralToLiquidate);

        //send gas compensation to liquidator
        lusdToken.transferFrom(address(gasPool), msg.sender, LUSD_GAS_COMPENSATION);

        // send liquidator his share
        activePool.sendETH(msg.sender, collateralCompensation);
    }

    function _closeVault(address _borrower, Status _status) internal {
        vaults[_borrower].status = _status;
        vaults[_borrower].collateral = 0;
        vaults[_borrower].debt = 0;

        sortedVaults.remove(_borrower);
    }

    function _getCurrentVaultAmounts(address _borrower) internal view returns(uint256, uint256) {
        uint256 currentETH = vaults[_borrower].collateral;
        uint256 currentLUSDDebt = vaults[_borrower].debt;

        return (currentETH, currentLUSDDebt);
    }

    modifier onlyBorrowingContract {
        require(msg.sender == borrowingAddress, "VaultManager: Invalid borrowing contract");
        _;
    }
}