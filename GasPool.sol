// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./LUSDToken.sol";

// Hold Gas compensations
contract GasPool {
    constructor(LUSDToken _lusdToken, address _spender) {
        _lusdToken.approve(_spender, 2**256 - 1);
    }
}