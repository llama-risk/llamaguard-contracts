// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { DeployStructs } from "./DeployStructs.sol";

/// @notice Sepolia uses the deployer as both owner and updater (passed in at call site).
///         The dedicated `script/sepolia/DeploySepolia.s.sol` script does that wiring. The
///         multi-chain `DeployAnyChain.s.sol` calls `getXxxConfig(broadcaster)` and gets the
///         same defaults so a dry-run against the sepolia RPC works without extra envs.
library SepoliaConfig {
    function getRegistryConfig(address deployer) internal pure returns (DeployStructs.RegistryDeployConfig memory) {
        return DeployStructs.RegistryDeployConfig({ owner: deployer, updater: deployer });
    }

    function getRouterConfig(address deployer) internal pure returns (DeployStructs.RouterDeployConfig memory) {
        return DeployStructs.RouterDeployConfig({
            owner: deployer,
            updater: deployer,
            initialWorkflowId: bytes32(0),
            initialForwarder: address(0),
            initialAuthor: address(0),
            initialWorkflowName: bytes10(0),
            initialRiskOracle: address(0),
            initialPublishSelector: bytes4(0),
            initialAgentHub: address(0),
            initialAgentIds: new uint256[](0),
            initialMaxReportAgeSeconds: 0
        });
    }
}
