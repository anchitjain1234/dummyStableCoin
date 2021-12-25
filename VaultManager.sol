// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./Base.sol";

import "./SortedVaults.sol";
import "./PriceFeed.sol";
import "./LiquidityMath.sol";
import "./StabilityPool.sol";
import "./StakingPool.sol";
import "./ActivePool.sol";
import "./GasPool.sol";
import "./LUSDToken.sol";


import "hardhat/console.sol";

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";


contract VaultManager is Base, Ownable {
    SortedVaults public sortedVaults;
    PriceFeed public priceFeed;
    StabilityPool public stabilityPool;
    StakingPool public stakingPool;
    ActivePool public activePool;
    LUSDToken public lusdToken;
    GasPool public gasPool;

    uint256 public baseRate;

    address public borrowingAddress;

    // latest fee operation (redemption or new LUSD issuance)
    uint256 public lastFeeOperationTime;

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

    function setAddresses(address _priceFeedAddress, StabilityPool _stabilityPool, ActivePool _activePool, LUSDToken _lusdToken, GasPool _gasPool, StakingPool _stakingPool) external onlyOwner {
        priceFeed = PriceFeed(_priceFeedAddress);
        stabilityPool = _stabilityPool;
        activePool = _activePool;
        lusdToken = _lusdToken;
        gasPool = _gasPool;
        stakingPool = _stakingPool;

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

    function getBorrowingFee(uint _LUSDDebt) external view returns (uint) {
        return _calcBorrowingFee(getBorrowingRate(), _LUSDDebt);
    }
    
    function _calcBorrowingFee(uint _borrowingRate, uint _LUSDDebt) internal pure returns (uint) {
        return _borrowingRate * _LUSDDebt / DECIMAL_PRECISION;
    }
    
    function getBorrowingRate() public view returns (uint) {
        return _calcBorrowingRate(baseRate);
    }

    function _calcBorrowingRate(uint _baseRate) internal pure returns (uint) {
        return LiquidityMath._min(
            BORROWING_FEE_FLOOR + _baseRate,
            MAX_BORROWING_FEE
        );
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
        console.log("lusdInStabilityPool %s", lusdInStabilityPool);
        require(lusdInStabilityPool >= currentLUSDDebt, "VaultManager: Insufficient funds in stability pool");

        // calculate collateral compensation
        uint256 collateralCompensation = currentETH / LIQUIDATOR_FEE_PERCENT_DIVISOR;
        uint256 collateralToLiquidate = currentETH - collateralCompensation;
        console.log("collateralCompensation %s, collateralToLiquidate %s", collateralCompensation, collateralToLiquidate);

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

    function redemption(uint256 _amountToRedeem) external {
        require(lusdToken.balanceOf(msg.sender) >= _amountToRedeem, "VaultManager: Insufficient balance");

        uint256 price = priceFeed.getPrice();
        console.log("ETH Price %s: ", price);

        // for simplicity always redeeming from the last vault, rather than going through all the vaults until the complete amount is redeemed
        address borrowerToRedeem = sortedVaults.getLast();

        // max amount to redeem is limited by the debt amount of the borrower
        uint256 maxAmountToRedeem = LiquidityMath._min(_amountToRedeem, vaults[borrowerToRedeem].debt - LUSD_GAS_COMPENSATION);
        console.log("LUSD to redeem %s", maxAmountToRedeem);

        // eth amount equivalent in USD
        uint256 ethAmountToRedeem = maxAmountToRedeem * DECIMAL_PRECISION / price;
        console.log("Eth to redeem %s", ethAmountToRedeem);

        uint256 newDebt = vaults[borrowerToRedeem].debt - maxAmountToRedeem;
        uint256 newCollateral = vaults[borrowerToRedeem].collateral - ethAmountToRedeem;
        console.log("newDebt %s", newDebt);
        console.log("newCollateral %s", newCollateral);

        if (newDebt == LUSD_GAS_COMPENSATION) {
            _closeVault(borrowerToRedeem, Status.closedByRedemption);
        } else {
            uint256 newNICR = LiquidityMath._computeNominalCR(newCollateral, newDebt);
            sortedVaults.reInsert(borrowerToRedeem, newNICR);

            console.log("Old debt %s", vaults[borrowerToRedeem].debt);
            console.log("Old collateral %s", vaults[borrowerToRedeem].collateral);
            vaults[borrowerToRedeem].debt = newDebt;
            vaults[borrowerToRedeem].collateral = newCollateral;
        }

        uint256 totalSystemDebt = activePool.getLUSDDebt();
        console.log("totalSystemDebt %s", totalSystemDebt);

        // decay the base rate
        _updateBaseRateFromRedemption(ethAmountToRedeem, price, totalSystemDebt);

        // Calculate the redemption fee in ETH
        uint256 ethFee = _getRedemptionFee(ethAmountToRedeem);
        console.log("ethFee %s", ethFee);

        // Send the ETH fee to the LQTY staking contract
        activePool.sendETH(address(stakingPool), ethFee);
        stakingPool.increaseETHFees(ethFee);

        uint256 ethToSendToRedeemer = ethAmountToRedeem - ethFee;
        console.log("ethToSendToRedeemer %s", ethToSendToRedeemer);
       
        // Burn the total LUSD that is cancelled with debt
        lusdToken.burn(msg.sender, maxAmountToRedeem);
        
        // Update Active Pool LUSD
        activePool.decreaseLUSDDebt(maxAmountToRedeem);
        
        // send ETH to redeemer
        activePool.sendETH(msg.sender, ethToSendToRedeemer);

    }

    function decayBaseRateFromBorrowing() external onlyBorrowingContract {
        uint decayedBaseRate = _calcDecayedBaseRate();
        assert(decayedBaseRate <= DECIMAL_PRECISION);  // The baseRate can decay to 0

        baseRate = decayedBaseRate;

        _updateLastFeeOpTime();
    }

    function _updateBaseRateFromRedemption(uint256 _ETHDrawn,  uint256 _price, uint256 _totalLUSDSupply) internal returns(uint) {
        uint decayedBaseRate = _calcDecayedBaseRate();

        /* Convert the drawn ETH back to LUSD at face value rate (1 LUSD:1 USD), in order to get
        * the fraction of total supply that was redeemed at face value. */
        uint redeemedLUSDFraction = (_ETHDrawn * _price) / _totalLUSDSupply;

        uint newBaseRate = decayedBaseRate + (redeemedLUSDFraction / BETA);
        newBaseRate = LiquidityMath._min(newBaseRate, DECIMAL_PRECISION); // cap baseRate at a maximum of 100%

        baseRate = newBaseRate;

        _updateLastFeeOpTime();

        return newBaseRate;
    }

    function _getRedemptionFee(uint _ETHDrawn) internal view returns (uint) {
        return _calcRedemptionFee(getRedemptionRate(), _ETHDrawn);
    }
    
    function _calcRedemptionFee(uint _redemptionRate, uint _ETHDrawn) internal pure returns (uint) {
        uint redemptionFee = _redemptionRate * _ETHDrawn / DECIMAL_PRECISION;
        require(redemptionFee < _ETHDrawn, "TroveManager: Fee would eat up all returned collateral");
        return redemptionFee;
    }
    
    function getRedemptionRate() public view returns (uint) {
        return _calcRedemptionRate(baseRate);
    }
    
    function _calcRedemptionRate(uint _baseRate) internal pure returns (uint) {
        return LiquidityMath._min(
            REDEMPTION_FEE_FLOOR + _baseRate,
            DECIMAL_PRECISION // cap at a maximum of 100%
        );
    }

    function _calcDecayedBaseRate() internal view returns (uint) {
        uint minutesPassed = _minutesPassedSinceLastFeeOp();
        console.log("MinutesPassed %s", minutesPassed);
        
        uint decayFactor = LiquidityMath._decPow(MINUTE_DECAY_FACTOR, minutesPassed);

        return baseRate * decayFactor / DECIMAL_PRECISION;
    }

    function _minutesPassedSinceLastFeeOp() internal view returns (uint) {
        return block.timestamp - lastFeeOperationTime / SECONDS_IN_ONE_MINUTE;
    }

    function _updateLastFeeOpTime() internal {
        uint timePassed = block.timestamp - lastFeeOperationTime;

        if (timePassed >= SECONDS_IN_ONE_MINUTE) {
            lastFeeOperationTime = block.timestamp;
        }
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