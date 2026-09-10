// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { Addresses } from "./Addresses.sol";
import { DeployStructs } from "./DeployStructs.sol";

library PlasmaConfig {
    function getRegistryConfig() internal pure returns (DeployStructs.RegistryDeployConfig memory) {
        return DeployStructs.RegistryDeployConfig({
            owner: Addresses.PLASMA_STAGING_OWNER, updater: Addresses.PLASMA_STAGING_UPDATER
        });
    }

    function getRouterConfig() internal pure returns (DeployStructs.RouterDeployConfig memory) {
        return DeployStructs.RouterDeployConfig({
            owner: Addresses.PLASMA_STAGING_OWNER,
            updater: Addresses.PLASMA_STAGING_UPDATER,
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
