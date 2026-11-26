// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { MockERC20 } from "./MockERC20.sol";

/// @title MockAToken
/// @notice aToken stand-in whose `totalSupply()` is the supplied amount of a MockPoolV3 reserve (the SUPPLY
///         level of the RVM). Open mint and burn, so a handler can model supply and withdraw.
contract MockAToken is MockERC20 {
    constructor(uint8 decimals_) MockERC20("aToken", "aT", decimals_) { }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
