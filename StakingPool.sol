// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

// Hold borrowing fees + Redemption fee rewards
contract StakingPool is Ownable {
    uint256 public totalETHFees; // on redemptions
    uint256 public totalLUSDFees; // on borrowing

    address public borrowingAddress;
    address public vaultManagerAddress;

    function setAddresses(address _borrowingAddress, address _vaultManagerAddress) external onlyOwner {
        borrowingAddress = _borrowingAddress;
        vaultManagerAddress = _vaultManagerAddress;

        //renounces ownership so that this method can't be called anymore
        renounceOwnership();
    }

    function increaseLUSDFees(uint256 _amount) external onlyBorrowingContract {
        totalLUSDFees += _amount;
    }

    function increaseETHFees(uint256 _amount) external {
        totalETHFees += _amount;
    }

    modifier onlyBorrowingContract {
        require(msg.sender == borrowingAddress, "StakingPool: Invalid borrowing contract");
        _;
    }

    modifier onlyVaultManagerContract {
        require(msg.sender == vaultManagerAddress, "StakingPool: Invalid vault manager contract");
        _;
    }

    // modifier onlyOwner {
    //     require (msg.sender == ownerAddress, "StakingPool: Invalid owner contract");
    //     _;
    // }
}