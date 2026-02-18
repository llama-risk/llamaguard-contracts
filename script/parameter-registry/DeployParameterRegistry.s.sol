// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { ParameterRegistry } from "../../src/ParameterRegistry.sol";
import { BaseScript } from "../Base.s.sol";
import { DeployStructs } from "../config/DeployStructs.sol";
import { MainnetConfig } from "../config/MainnetConfig.sol";
import { SepoliaConfig } from "../config/SepoliaConfig.sol";
import { AnvilConfig } from "../config/AnvilConfig.sol";
import { Addresses } from "../config/Addresses.sol";
import { console2 } from "forge-std/Test.sol";

/// @title DeployParameterRegistry
/// @notice Simplified deployment script for ParameterRegistry
/// @dev Deploys registry with deployer as initial owner/updater
contract DeployParameterRegistry is BaseScript {
    /// @notice Deploy ParameterRegistry
    /// @return parameterRegistry The deployed contract
    function run() public broadcast returns (ParameterRegistry parameterRegistry) {
        console2.log("=========================================");
        console2.log("Deploy ParameterRegistry");
        console2.log("=========================================");
        console2.log("Chain ID:", block.chainid);
        console2.log("Deployer:", broadcaster);

        parameterRegistry = new ParameterRegistry(broadcaster, broadcaster);

        console2.log("[OK] ParameterRegistry:", address(parameterRegistry));
        console2.log("  Owner:", parameterRegistry.owner());
        console2.log("  Updater:", parameterRegistry.updater());
        console2.log("=========================================");
    }
}
