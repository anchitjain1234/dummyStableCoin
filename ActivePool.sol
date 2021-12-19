// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

//Hold ETH + LUSD debt
contract ActivePool is Ownable {
    uint256 public totalETHDeposited;
    uint256 public totalLUSDDebt;

    address public borrowingAddress;
    address public vaultManagerAddress;
    address public stabilityPoolAddress;

    function setAddresses(address _vaultManagerAddress, address _stabilityPoolAddress) external onlyOwner {
        borrowingAddress = msg.sender;
        vaultManagerAddress = _vaultManagerAddress;
        stabilityPoolAddress = _stabilityPoolAddress;
        renounceOwnership();
    }

    function getETHDeposited() external view returns(uint256) {
        return totalETHDeposited;
    }

    function getLUSDDebt() external view returns(uint256) {
        return totalLUSDDebt;
    }

    function increaseLUSDDebt(uint256 _amount) external onlyBorrowingContract {
        totalLUSDDebt += _amount;
    }

    function decreaseLUSDDebt(uint256 _amount) external onlyBorrowingOrVaultManagerOrStabilityPoolContract {
        totalLUSDDebt -= _amount;
    }

    receive() external payable onlyBorrowingContract {
        totalETHDeposited += msg.value;
    }

    function sendETH(address _account, uint256 _amount) external onlyBorrowingOrVaultManagerOrStabilityPoolContract {
        totalETHDeposited -= _amount;

        (bool success, ) = _account.call{value : _amount}("");
        require(success, "BorrActivePool: Sending ETH to User failed");
    }

    modifier onlyBorrowingContract {
        require(msg.sender == borrowingAddress, "ActivePool: Invalid borrowing contract");
        _;
    }

    modifier onlyBorrowingOrVaultManagerOrStabilityPoolContract {
        require(msg.sender == borrowingAddress ||
                msg.sender == vaultManagerAddress ||
                msg.sender == stabilityPoolAddress,
                 "ActivePool: Invalid onlyBorrowingOrVaultManagerOrStabilityPoolContract contract");
        _;
    }
}