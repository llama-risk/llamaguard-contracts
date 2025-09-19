// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.26 <0.9.0;

import { ParameterRegistry } from "../src/ParameterRegistry.sol";

import { BaseScript } from "./Base.s.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/guides/scripting-with-solidity
contract Deploy is BaseScript {
    function run() public broadcast returns (ParameterRegistry registry) {
        address owner = msg.sender;
        address updater = msg.sender; // Set to the same address for simplicity
        registry = new ParameterRegistry(owner, updater);
    }
}
