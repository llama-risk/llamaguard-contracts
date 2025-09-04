// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29 <0.9.0;

import { ParameterRegistry } from "../src/ParameterRegistry.sol";
import { BaseScript } from "./Base.s.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/guides/scripting-with-solidity
contract DeployParameterRegistry is BaseScript {
    function run() public broadcast returns (ParameterRegistry parameterRegistry) {
        // Read environment variables for constructor arguments
        address owner = vm.envAddress("OWNER_ADDRESS");
        address updater = vm.envAddress("UPDATER_ADDRESS");

        // Deploy the contract
        parameterRegistry = new ParameterRegistry(owner, updater);
    }
}
