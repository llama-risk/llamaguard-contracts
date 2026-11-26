// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { RiskOracle } from "aave-v3-risk-stewards/contracts/dependencies/RiskOracle.sol";
import { AaveBorrowCapAgent } from "aave-risk-agents/src/contracts/agent/AaveBorrowCapAgent.sol";
import { LlamaguardRiskOracleRouter } from "../../../src/LlamaguardRiskOracleRouter.sol";
import { CapsParameterRegistry } from "../../../src/caps-oracle/CapsParameterRegistry.sol";
import { CapsRangeValidationModuleV3 } from "../../../src/caps-oracle/CapsRangeValidationModuleV3.sol";
import { CapsReducerOracle } from "../../../src/caps-oracle/CapsReducerOracle.sol";
import { CapsConfig } from "./CapsConfig.sol";
import { CapsDeployment } from "./CapsDeployment.sol";
import { CapsScript } from "./CapsScript.sol";

/// @title DeployCaps
/// @notice Step 1: deploys the caps stack on the Pool and AgentHub it runs on. Only constructors, no
///         configuration. Owners are set at construction where the contract takes one; the RiskOracle and the
///         Router start with the deployer and are handed over at the end of step 2.
///
///           CAPS_DEPLOYMENT=<label> forge script script/risk-oracles/caps/1_DeployCaps.s.sol \
///             --rpc-url <rpc> --account <keystore> --sender "$ETH_FROM" [--broadcast --verify]
contract DeployCaps is CapsScript {
    function run() external {
        (string memory label, CapsConfig.Config memory config, CapsDeployment.Deployment memory deployment) = _context();
        _save(label, deploy(config, deployment, broadcaster));
    }

    function deploy(
        CapsConfig.Config memory config,
        CapsDeployment.Deployment memory deployment,
        address sender
    )
        public
        returns (CapsDeployment.Deployment memory)
    {
        CapsConfig.Market memory market = config.market;
        CapsConfig.Roles memory roles = config.roles;
        address pool = _stackPool(market, deployment);
        address hub = _agentHub(market, deployment);
        require(pool != address(0) && hub != address(0), "DeployCaps: no Pool or AgentHub, run step 0 first");
        require(deployment.rvm == address(0), "DeployCaps: already deployed");

        _begin(sender);
        deployment.riskOracle = address(new RiskOracle(market.riskOracleDescription, new address[](0), new string[](0)));
        deployment.router = address(new LlamaguardRiskOracleRouter(sender));
        deployment.registry = address(new CapsParameterRegistry(roles.registryOwner, roles.registryUpdater));
        CapsRangeValidationModuleV3 rvm = new CapsRangeValidationModuleV3(
            roles.rvmOwner,
            hub,
            pool,
            roles.riskCouncil,
            CapsConfig.borrowUpdateType(market),
            CapsConfig.supplyUpdateType(market)
        );
        deployment.rvm = address(rvm);
        deployment.reducer = address(new CapsReducerOracle(rvm));
        deployment.raiseAgent = address(new AaveBorrowCapAgent(hub, address(rvm), market.updateTypeSuffix, pool));
        deployment.cutAgent = address(new AaveBorrowCapAgent(hub, address(rvm), market.updateTypeSuffix, pool));
        _end("Step 1: deploy");

        console2.log("RiskOracle:", deployment.riskOracle);
        console2.log("Router:    ", deployment.router);
        console2.log("Registry:  ", deployment.registry);
        console2.log("RVM:       ", deployment.rvm);
        console2.log("Reducer:   ", deployment.reducer);
        console2.log("RaiseAgent:", deployment.raiseAgent);
        console2.log("CutAgent:  ", deployment.cutAgent);
        return deployment;
    }
}
