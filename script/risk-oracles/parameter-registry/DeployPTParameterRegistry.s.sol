// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { BaseScript } from "../Base.s.sol";
import { PTParameterRegistry } from "../../../src/PTParameterRegistry.sol";

/// @notice Stand-alone registry deploy. Owner and updater default to the broadcaster; override
///         with $REGISTRY_OWNER and $REGISTRY_UPDATER for production deployments.
contract DeployPTParameterRegistry is BaseScript {
    function run() public broadcast returns (PTParameterRegistry registry) {
        address owner = vm.envOr({ name: "REGISTRY_OWNER", defaultValue: broadcaster });
        address updater = vm.envOr({ name: "REGISTRY_UPDATER", defaultValue: broadcaster });
        registry = new PTParameterRegistry(owner, updater);
    }
}
