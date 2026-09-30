// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { BaseScript } from "../../Base.s.sol";
import { ParameterRegistry } from "../../../src/ParameterRegistry.sol";
import { AvalancheParameterRegistryConfig } from "./AvalancheParameterRegistryConfig.sol";

/// @title DeployAvalancheParameterRegistry
/// @notice Deploys the NAV `ParameterRegistry` on Avalanche. The owner is the Aave governance
///         executor. The updater is the Avalanche Risk Council.
/// @dev    Set `ETH_FROM` to the deployer, then run:
///         forge script script/parameter-registry/avalanche/DeployAvalancheParameterRegistry.s.sol \
///           --rpc-url avalanche --broadcast --verify --chain 43114
contract DeployAvalancheParameterRegistry is BaseScript {
    /// @dev Index 0 of the `BaseScript` test mnemonic. `BaseScript` uses this key when `ETH_FROM`
    ///      and `MNEMONIC` are not set.
    address internal constant TEST_MNEMONIC_ACCOUNT = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    function run() public broadcast returns (ParameterRegistry registry) {
        require(broadcaster != TEST_MNEMONIC_ACCOUNT, "DeployAvalancheParameterRegistry: set ETH_FROM to the deployer");
        AvalancheParameterRegistryConfig.validate();

        console2.log("=============================================");
        console2.log("Avalanche NAV ParameterRegistry deployment");
        console2.log("=============================================");
        console2.log("Broadcaster:", broadcaster);
        console2.log("Owner (Aave executor):", AvalancheParameterRegistryConfig.REGISTRY_OWNER);
        console2.log("Updater (Risk Council):", AvalancheParameterRegistryConfig.REGISTRY_UPDATER);

        registry = deploy();

        console2.log("");
        console2.log(string.concat("OUTPUT:PARAMETER_REGISTRY=", vm.toString(address(registry))));
    }

    function deploy() public returns (ParameterRegistry registry) {
        registry = new ParameterRegistry(
            AvalancheParameterRegistryConfig.REGISTRY_OWNER, AvalancheParameterRegistryConfig.REGISTRY_UPDATER
        );
        _verify(registry);
    }

    /// @dev Reads every role back from the deployed contract.
    function _verify(ParameterRegistry registry) internal view {
        require(
            registry.owner() == AvalancheParameterRegistryConfig.REGISTRY_OWNER,
            "DeployAvalancheParameterRegistry: owner mismatch"
        );
        require(registry.pendingOwner() == address(0), "DeployAvalancheParameterRegistry: pending owner set");
        require(
            registry.updater() == AvalancheParameterRegistryConfig.REGISTRY_UPDATER,
            "DeployAvalancheParameterRegistry: updater mismatch"
        );
    }
}
