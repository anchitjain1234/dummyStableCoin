// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./LUSDToken.sol";

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

// Hold LUSD deposited + ETH liquidated
contract StabilityPool is Ownable {
    uint256 public totalLUSDDeposits;
    uint256 public totalETHDeposited;

    mapping(address => uint256) public deposits;

    LUSDToken public lusdToken;
    address public vaultManagerAddress;
    address public activePoolAddress;

    function setAddresses(address _lusdTokenAddress, address _vaultManagerAdddress, address _activePoolAddress) external onlyOwner {
        lusdToken = LUSDToken(_lusdTokenAddress);
        vaultManagerAddress = _vaultManagerAdddress;
        activePoolAddress = _activePoolAddress;
        renounceOwnership();
    }

    function deposit(uint256 _lusdAmount) external {
        deposits[msg.sender] += _lusdAmount;
        totalLUSDDeposits += _lusdAmount;

        lusdToken.transferFrom(msg.sender, address(this), _lusdAmount);
    }

    function getTotalLUSDDeposits() external view returns(uint256) {
        return totalLUSDDeposits;
    }

    function offSet(uint256 _lusdDebt) external onlyVaultManager {
        totalLUSDDeposits -= _lusdDebt;
        lusdToken.burn(address(this), _lusdDebt);
    }

    receive() external payable onlyActivePool {
        totalETHDeposited += msg.value;
    }

    function getTotalETHDeposits() external view returns(uint256) {
        return totalETHDeposited;
    }

    modifier onlyVaultManager {
        require(msg.sender == vaultManagerAddress, "StabilityPool: Sender is not vault manager");
        _;
    }

    modifier onlyActivePool {
        require(msg.sender == activePoolAddress, "StabilityPool: Sender is not Active Pool");
        _;
    }
}