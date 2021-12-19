// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./Base.sol";

import "./PriceFeed.sol";

import "./GasPool.sol";
import "./ActivePool.sol";
import "./StakingPool.sol";
import "./StabilityPool.sol";

import "./VaultManager.sol";
import "./LUSDToken.sol";

import "hardhat/console.sol";


contract Borrowing is Base {
    PriceFeed public priceFeed;

    GasPool public gasPool;
    StabilityPool public stabilityPool;
    ActivePool public activePool;
    StakingPool public stakingPool;

    VaultManager public vaultManager;
    LUSDToken public lusdToken;

    constructor() {
        priceFeed = new PriceFeed();
        priceFeed.setPrice(1000 * 10**18);

        gasPool = new GasPool();
        stabilityPool = new StabilityPool();
        activePool = new ActivePool();
        stakingPool = new StakingPool();

        vaultManager = new VaultManager();

        lusdToken = new LUSDToken(address(vaultManager), address(stabilityPool));

        stakingPool.setAddresses(address(this), address(vaultManager));
        activePool.setAddresses(address(vaultManager), address(stabilityPool));
    }

    function borrow(uint256 _lusdAmount) external payable {
        // get price from oracle
        uint256 price = priceFeed.getPrice();

        uint256 debt = _lusdAmount * DECIMAL_PRECISION;
        // msg.value is the ether amount sent
        uint256 collateralRatio = msg.value * price / debt;
        console.log("Price: %s,\n Debt: %s,\n Ratio: %s", 
                    price / DECIMAL_PRECISION, 
                    debt / DECIMAL_PRECISION, 
                    collateralRatio / DECIMAL_PRECISION);

        require(collateralRatio >= MINIMUM_COLLATERAL_RATIO, "Borrowing: Invalid Collateral Ratio");

        // get borrowing fee
        uint256 borrowingFee = vaultManager.getBorrowingFee(debt);
        console.log("borrowingFee: %s", borrowingFee);

        // send borrowing fee to staking pool
        stakingPool.increaseLUSDFees(borrowingFee);
        lusdToken.mint(address(stakingPool), borrowingFee);

        // mint LUSD tokens borrowed by user
        lusdToken.mint(msg.sender, debt);
        console.log("USer token balance: %s", lusdToken.balanceOf(address(msg.sender)));

        // calculate user's composite debt(borrowingFee + gas compensation + amount req)
        uint256 compositeDebt = borrowingFee + debt + LUSD_GAS_COMPENSATION;
        console.log("USer compositeDebt: %s",compositeDebt);

        //create a vault for the user
        vaultManager.createVault(msg.sender, msg.value, compositeDebt);

        //send collateral to active pool
        (bool success, ) = address(activePool).call{value : msg.value}("");
        require(success, "Borrowing: Sending ETH to ActivePool failed");

        //increase Debt of active pool
        activePool.increaseLUSDDebt(compositeDebt);
        console.log("Active pool LUSD debt: %s", activePool.getLUSDDebt());

        //send gas comp to gas pool
        lusdToken.mint(address(gasPool), LUSD_GAS_COMPENSATION);
        console.log("Gaspool token balance: %s", lusdToken.balanceOf(address(gasPool)));
    }

    function repay() external {
        //get user's collateral and debt
        uint256 collateral = vaultManager.getVaultCollateral(msg.sender);
        uint256 debt = vaultManager.getVaultDebt(msg.sender);
        console.log("DEBT %s", debt);
        console.log("User balance %s", lusdToken.balanceOf(msg.sender));

        //calculate debt to repay
        uint256 debtToRepay = debt - LUSD_GAS_COMPENSATION;
        console.log("DEBT %s", debtToRepay);

        //validate that user has enough funds
        require(lusdToken.balanceOf(msg.sender) >= debtToRepay, "Borrowing: Insufficienet funds to repay");

        //burn the repaid LUSD from user's balance
        lusdToken.burn(msg.sender, debtToRepay);

        //decrease active pool debt
        activePool.decreaseLUSDDebt(debtToRepay);

        //close the vault
        vaultManager.closeVault(msg.sender);

        //burn gas compensation from gas pool
        lusdToken.burn(address(gasPool), LUSD_GAS_COMPENSATION);
        activePool.decreaseLUSDDebt(LUSD_GAS_COMPENSATION);

        //send collateral back to user
        activePool.sendETH(msg.sender, collateral);
    }
}