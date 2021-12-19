// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";

import "hardhat/console.sol";

//ERC20 with mint and burn restricted to certain owners
contract LUSDToken is ERC20 {
    // mint -> Only callable from borrowing
    // burn -> Borrowing, VaultManager, StabilityPool

    address public borrowingAddress;
    address public vaultManagerAddress;
    address public stabilityPoolAddress;

    constructor(address _vaultManagerAddress, address _stabilityPoolAddress) ERC20("LUSDToken", "LUSD") {
        //borrowing contract initializes this
        borrowingAddress = msg.sender;
        vaultManagerAddress = _vaultManagerAddress;
        stabilityPoolAddress = _stabilityPoolAddress;
    }

    function mint(address _account, uint256 _amount) external onlyBorrowingContract {
        console.log("calling mint for amount %s", _amount);
        _mint(_account, _amount);
    }

    function burn(address _account, uint256 _amount) external onlyBorrowingOrVaultManagerOrStabilityPoolContract {
        console.log("calling burn for amount %s", _amount);
        _burn(_account, _amount);
    }

    modifier onlyBorrowingContract {
        require(msg.sender == borrowingAddress, "LUSDToken: Invalid borrowing contract");
        _;
    }

    modifier onlyBorrowingOrVaultManagerOrStabilityPoolContract {
        require(msg.sender == borrowingAddress || 
                msg.sender == vaultManagerAddress || 
                msg.sender == stabilityPoolAddress,
                 "LUSDToken: Invalid BorrowingOrVaultManagerOrStabilityPoolContract contract");
        _;
    }
}