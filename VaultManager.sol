// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./Base.sol";

import "./SortedVaults.sol";

contract VaultManager is Base {
    SortedVaults public sortedVaults;

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