// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { BaseScript } from "./Base.s.sol";
import { PTParameterRegistry } from "../../src/PTParameterRegistry.sol";
import { LlamaguardRiskOracleRouter } from "../../src/LlamaguardRiskOracleRouter.sol";
import { Addresses } from "./config/Addresses.sol";
import { DeployStructs } from "./config/DeployStructs.sol";
import { EthereumConfig } from "./config/EthereumConfig.sol";
import { PlasmaConfig } from "./config/PlasmaConfig.sol";
import { MantleConfig } from "./config/MantleConfig.sol";
import { SepoliaConfig } from "./config/SepoliaConfig.sol";
import { PTEmaConfig } from "./config/PTEmaConfig.sol";
import { PTEmaDeployer } from "./pt-ema-oracle/PTEmaDeployer.sol";

/// @notice Multi-chain deploy. Reads `block.chainid` and dispatches to the matching config.
///         Ethereum / Plasma / Mantle pull constants from `Addresses.sol` (must be filled in
///         before broadcasting). Sepolia falls back to the broadcaster as owner+updater.
///
///         When the configured owner is not the broadcaster, the script deploys the contracts
///         but does NOT wire `setUpdater` or `addRoute` — those calls have to be made by the
///         multisig owner in a follow-up transaction. The script logs this explicitly so the
///         operator knows what's still pending after broadcast.
contract DeployAnyChain is BaseScript {
    error UnsupportedChain(uint256 chainId);

    struct PTEmaDeployed {
        address oracle;
        address oracleProxy;
    }

    function run()
        public
        broadcast
        returns (PTParameterRegistry registry, LlamaguardRiskOracleRouter router, PTEmaDeployed memory ptEma)
    {
        DeployStructs.RegistryDeployConfig memory regCfg;
        DeployStructs.RouterDeployConfig memory routerCfg;
        PTEmaConfig.PTEmaDeployConfig memory ptEmaCfg;
        bool ptEmaConfigured;

        uint256 chainId = block.chainid;
        if (chainId == Addresses.MAINNET) {
            regCfg = EthereumConfig.getRegistryConfig();
            routerCfg = EthereumConfig.getRouterConfig();
        } else if (chainId == Addresses.PLASMA) {
            regCfg = PlasmaConfig.getRegistryConfig();
            routerCfg = PlasmaConfig.getRouterConfig();
            ptEmaCfg = PTEmaConfig.getPlasmaConfig();
            ptEmaConfigured = true;
        } else if (chainId == Addresses.MANTLE) {
            regCfg = MantleConfig.getRegistryConfig();
            routerCfg = MantleConfig.getRouterConfig();
        } else if (chainId == Addresses.SEPOLIA) {
            regCfg = SepoliaConfig.getRegistryConfig(broadcaster);
            routerCfg = SepoliaConfig.getRouterConfig(broadcaster);
            ptEmaCfg = PTEmaConfig.getSepoliaConfig(broadcaster);
            ptEmaConfigured = true;
        } else {
            revert UnsupportedChain(chainId);
        }

        console2.log("DeployAnyChain: chainId", chainId);
        console2.log("DeployAnyChain: broadcaster", broadcaster);
        console2.log("DeployAnyChain: registry owner", regCfg.owner);
        console2.log("DeployAnyChain: registry updater", regCfg.updater);
        console2.log("DeployAnyChain: router owner", routerCfg.owner);
        console2.log("DeployAnyChain: router updater (configured)", routerCfg.updater);

        registry = new PTParameterRegistry(regCfg.owner, regCfg.updater);
        router = new LlamaguardRiskOracleRouter(routerCfg.owner);

        if (routerCfg.owner == broadcaster) {
            router.setUpdater(routerCfg.updater);
        } else {
            console2.log(
                "DeployAnyChain: router owner != broadcaster; setUpdater SKIPPED. Owner must call setUpdater post-deploy.",
                routerCfg.owner
            );
        }

        if (routerCfg.initialWorkflowId != bytes32(0)) {
            if (routerCfg.owner == broadcaster) {
                router.addRoute(
                    routerCfg.initialWorkflowId,
                    routerCfg.initialForwarder,
                    routerCfg.initialAuthor,
                    routerCfg.initialWorkflowName,
                    routerCfg.initialRiskOracle,
                    routerCfg.initialPublishSelector,
                    routerCfg.initialAgentHub,
                    routerCfg.initialAgentIds,
                    routerCfg.initialMaxReportAgeSeconds
                );
            } else {
                console2.log(
                    "DeployAnyChain: router owner != broadcaster; addRoute SKIPPED for workflowId.",
                    uint256(routerCfg.initialWorkflowId)
                );
            }
        }

        console2.log("DeployAnyChain: registry", address(registry));
        console2.log("DeployAnyChain: router", address(router));

        if (ptEmaConfigured) {
            ptEma = _deployPTEma(ptEmaCfg);
        }
    }

    function _deployPTEma(PTEmaConfig.PTEmaDeployConfig memory cfg) internal returns (PTEmaDeployed memory deployed) {
        PTEmaDeployer.Deployed memory d = PTEmaDeployer.deploy(cfg, broadcaster);
        deployed = PTEmaDeployed({ oracle: d.oracle, oracleProxy: d.oracleProxy });
    }
}
