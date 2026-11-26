// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { RiskOracle } from "aave-v3-risk-stewards/contracts/dependencies/RiskOracle.sol";
import { LlamaguardRiskOracleRouter } from "../../../src/LlamaguardRiskOracleRouter.sol";
import { CapsConfig } from "./CapsConfig.sol";
import { CapsDeployment } from "./CapsDeployment.sol";
import { CapsScript } from "./CapsScript.sol";

/// @title AddRoute
/// @notice Step 4, in the same sitting as `cre workflow deploy`: the Router route from the workflow to our RiskOracle
///         and the raise agent, then the throttle off. The workflow rejects any other throttle
///         (`routerThrottleMisconfigured`), and `addRoute` leaves the route frozen until `setRouteThrottle`.
///
///           CAPS_DEPLOYMENT=<label> forge script script/risk-oracles/caps/4_AddRoute.s.sol \
///             --sig "run(bytes32,bytes10)" <workflowId> <workflowName> \
///             --rpc-url <rpc> --account <keystore> --sender "$ETH_FROM" [--broadcast]
///
///         Both values come from `cre workflow hash` for the exact wasm and config being deployed.
contract AddRoute is CapsScript {
    function run(bytes32 workflowId, bytes10 workflowName) external {
        (string memory label, CapsConfig.Config memory config, CapsDeployment.Deployment memory deployment) = _context();
        addRoute(config.market, CapsConfig.loadRoute(label), deployment, workflowId, workflowName, broadcaster);
    }

    function addRoute(
        CapsConfig.Market memory market,
        CapsConfig.Route memory route,
        CapsDeployment.Deployment memory deployment,
        bytes32 workflowId,
        bytes10 workflowName,
        address sender
    )
        public
    {
        require(deployment.raiseAgentId != deployment.cutAgentId, "AddRoute: run step 2 first");
        require(workflowId != bytes32(0) && workflowName != bytes10(0), "AddRoute: workflow id and name are required");
        LlamaguardRiskOracleRouter router = LlamaguardRiskOracleRouter(deployment.router);
        bytes memory addRouteCall = _addRouteCall(market, route, deployment, workflowId, workflowName);

        _begin(sender);
        _call("Router: route", Ownable(address(router)).owner(), address(router), addRouteCall);
        _call(
            "Router: throttle off",
            router.updater(),
            address(router),
            abi.encodeCall(LlamaguardRiskOracleRouter.setRouteThrottle, (workflowId, 0, router.MAX_STEP_OFF()))
        );
        _end("Step 4: route");

        console2.log("Route added for workflow:");
        console2.logBytes32(workflowId);
    }

    /// @dev The route publishes in bulk to our RiskOracle and kicks only the raise agent.
    function _addRouteCall(
        CapsConfig.Market memory market,
        CapsConfig.Route memory route,
        CapsDeployment.Deployment memory deployment,
        bytes32 workflowId,
        bytes10 workflowName
    )
        private
        pure
        returns (bytes memory)
    {
        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = deployment.raiseAgentId;
        return abi.encodeCall(
            LlamaguardRiskOracleRouter.addRoute,
            (
                workflowId,
                route.forwarder,
                route.workflowOwner,
                workflowName,
                deployment.riskOracle,
                RiskOracle.publishBulkRiskParameterUpdates.selector,
                _agentHub(market, deployment),
                agentIds,
                route.maxReportAgeSeconds
            )
        );
    }
}
