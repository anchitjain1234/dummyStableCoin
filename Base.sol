// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

contract Base {
    uint256 constant public MINIMUM_COLLATERAL_RATIO = 1.1 * 10**18;

    uint256 constant public DECIMAL_PRECISION = 1e18;

    uint256 constant public BORROWING_FEE_FLOOR = DECIMAL_PRECISION / 1000 * 5; //0.5%

    uint256 constant public LUSD_GAS_COMPENSATION = 200e18;

    uint256 constant public LIQUIDATOR_FEE_PERCENT_DIVISOR = 200;

     /*
     * Half-life of 12h. 12h = 720 min
     * (1/2) = d^720 => d = (1/2)^(1/720)
     */
    uint constant public MINUTE_DECAY_FACTOR = 999037758833783000;
    
    uint constant public REDEMPTION_FEE_FLOOR = DECIMAL_PRECISION / 1000 * 5; // 0.5%
    
    uint constant public MAX_BORROWING_FEE = DECIMAL_PRECISION / 100 * 5; // 5%
        
    uint constant public NICR_PRECISION = 1e20;
    
    uint constant public PERCENT_DIVISOR = 200; // dividing by 200 yields 0.5%

    uint constant public SECONDS_IN_ONE_MINUTE = 60;
    
    /*
    * BETA: 18 digit decimal. Parameter by which to divide the redeemed fraction, in order to calc the new base rate from a redemption.
    * Corresponds to (1 / ALPHA) in the white paper.
    */
    uint constant public BETA = 2;

}