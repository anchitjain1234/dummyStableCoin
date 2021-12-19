// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

contract Base {
    uint256 constant public MINIMUM_COLLATERAL_RATIO = 1.1 * 10**18;

    uint256 constant public DECIMAL_PRECISION = 1e18;

    uint256 constant public BORROWING_FEE_FLOOR = DECIMAL_PRECISION / 1000 * 5; //0.5%

    uint256 constant public LUSD_GAS_COMPENSATION = 200e18;

}