// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { BaseScript } from "../Base.s.sol";
import { PTParameterRegistry } from "../../../src/PTParameterRegistry.sol";
import { LlamaguardRiskOracleRouter } from "../../../src/LlamaguardRiskOracleRouter.sol";
import { SepoliaConfig } from "../config/SepoliaConfig.sol";
import { DeployStructs } from "../config/DeployStructs.sol";

/// @notice Sepolia deploy: deployer is owner AND updater of both contracts. The router has no
///         pre-seeded route — wire one with a separate transaction after the CRE workflow is
///         registered upstream. Not a production posture; see `DeployAnyChain.s.sol` for the
///         multi-chain script that respects per-network owner / updater addresses.
contract DeploySepolia is BaseScript {
    function run() public broadcast returns (PTParameterRegistry registry, LlamaguardRiskOracleRouter router) {
        DeployStructs.RegistryDeployConfig memory rc = SepoliaConfig.getRegistryConfig(broadcaster);
        DeployStructs.RouterDeployConfig memory routerCfg = SepoliaConfig.getRouterConfig(broadcaster);

        console2.log("DeploySepolia: SEPOLIA test deploy - NOT a production posture.");
        console2.log("DeploySepolia: deployer == registry owner == registry updater ==", broadcaster);
        console2.log("DeploySepolia: deployer == router owner == router updater ==", broadcaster);

        registry = new PTParameterRegistry(rc.owner, rc.updater);
        router = new LlamaguardRiskOracleRouter(routerCfg.owner);
        router.setUpdater(routerCfg.updater);

        console2.log("DeploySepolia: registry", address(registry));
        console2.log("DeploySepolia: router", address(router));
    }
}
