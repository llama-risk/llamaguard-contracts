// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { BaseScript } from "../Base.s.sol";
import { LlamaguardRiskOracleRouter } from "../../../src/LlamaguardRiskOracleRouter.sol";
import { RouterSelectors } from "../RouterSelectors.sol";

/// @notice Post-deploy script that wires the Router with real CRE workflow IDs.
///         Run AFTER `cre workflow deploy` when the workflow IDs are known.
///
///         Required env vars:
///         - ROUTER_ADDRESS: address of deployed LlamaguardRiskOracleRouter
///         - RISK_ORACLE_ADDRESS: address of RiskOracle (for discount + risk-params)
///         - LLAMAGUARD_ORACLE_ADDRESS: address of LlamaGuardOracle (for EMA)
///         - AGENT_HUB_ADDRESS: address of AgentHub (or 0x0 to skip injection)
///         - FORWARDER_ADDRESS: production KeystoneForwarder on Sepolia
///         - WORKFLOW_AUTHOR: workflow owner address
///         - EMA_WORKFLOW_ID: bytes32 workflow ID for pendle_ema_oracle
///         - EMA_WORKFLOW_NAME: bytes10 workflow name (as bytes32 hex)
///         - DISCOUNT_WORKFLOW_ID: bytes32 workflow ID for pendle_discount_rate_oracle
///         - DISCOUNT_WORKFLOW_NAME: bytes10 workflow name (as bytes32 hex)
///         - DISCOUNT_AGENT_ID: uint256 agent ID for discount agent (0 to skip)
///         - RISK_PARAMS_WORKFLOW_ID: bytes32 workflow ID for pendle_risk_parameters_oracle
///         - RISK_PARAMS_WORKFLOW_NAME: bytes10 workflow name (as bytes32 hex)
///         - EMODE_AGENT_ID: uint256 agent ID for eMode agent (0 to skip)
contract RegisterWorkflows is BaseScript {
    uint64 internal constant DISCOUNT_MIN_DELAY_SECONDS = 1 days;
    uint64 internal constant DISCOUNT_MAX_STEP_BPS = 100;
    /// @dev Replay-guard age bound for the RiskOracle routes: 30 minutes, sized above
    ///      workflow execution plus delivery latency and well below the 3h cron interval.
    ///      The EMA route keeps the guard off (its LlamaGuardOracle payload enforces its
    ///      own deadline onchain).
    uint64 internal constant MAX_REPORT_AGE_SECONDS = 1800;

    struct Context {
        LlamaguardRiskOracleRouter router;
        address riskOracle;
        address llamaGuardOracle;
        address agentHub;
        address forwarder;
        address author;
    }

    function run() public broadcast {
        Context memory ctx = Context({
            router: LlamaguardRiskOracleRouter(vm.envAddress("ROUTER_ADDRESS")),
            riskOracle: vm.envAddress("RISK_ORACLE_ADDRESS"),
            llamaGuardOracle: vm.envAddress("LLAMAGUARD_ORACLE_ADDRESS"),
            agentHub: vm.envOr({ name: "AGENT_HUB_ADDRESS", defaultValue: address(0) }),
            forwarder: vm.envAddress("FORWARDER_ADDRESS"),
            author: vm.envAddress("WORKFLOW_AUTHOR")
        });

        _registerEmaRoute(ctx);
        _registerDiscountRoute(ctx);
        _registerRiskParamsRoute(ctx);

        console2.log("All workflow routes registered.");
    }

    function _buildAgentIds(uint256 agentId, address agentHub) internal pure returns (uint256[] memory) {
        if (agentId != 0 && agentHub != address(0)) {
            uint256[] memory ids = new uint256[](1);
            ids[0] = agentId;
            return ids;
        }
        return new uint256[](0);
    }

    function _registerEmaRoute(Context memory ctx) internal {
        bytes32 workflowId = vm.envBytes32("EMA_WORKFLOW_ID");
        bytes10 workflowName = bytes10(vm.envBytes32("EMA_WORKFLOW_NAME"));

        console2.log("Registering EMA workflow route...");
        console2.log("  workflowId:", uint256(workflowId));
        console2.log("  forwarder:", ctx.forwarder);
        console2.log("  author:", ctx.author);
        console2.log("  oracle:", ctx.llamaGuardOracle);

        ctx.router
            .addRoute(
                workflowId,
                ctx.forwarder,
                ctx.author,
                workflowName,
                ctx.llamaGuardOracle,
                RouterSelectors.UPDATE_LLAMAGUARD_SELECTOR,
                address(0),
                new uint256[](0),
                0
            );

        // EMA route: guard off (MAX_STEP_OFF) — allow any delta between publishes
        ctx.router.setRouteThrottle(workflowId, 0, ctx.router.MAX_STEP_OFF());
        console2.log("[OK] EMA workflow route registered (throttle: guard off)");
    }

    function _registerDiscountRoute(Context memory ctx) internal {
        bytes32 workflowId = vm.envBytes32("DISCOUNT_WORKFLOW_ID");
        bytes10 workflowName = bytes10(vm.envBytes32("DISCOUNT_WORKFLOW_NAME"));
        uint256 agentId = vm.envOr({ name: "DISCOUNT_AGENT_ID", defaultValue: uint256(0) });

        console2.log("Registering discount-rate workflow route...");
        console2.log("  workflowId:", uint256(workflowId));
        console2.log("  oracle:", ctx.riskOracle);

        ctx.router
            .addRoute(
                workflowId,
                ctx.forwarder,
                ctx.author,
                workflowName,
                ctx.riskOracle,
                RouterSelectors.PUBLISH_SINGLE_SELECTOR,
                agentId != 0 ? ctx.agentHub : address(0),
                _buildAgentIds(agentId, ctx.agentHub),
                MAX_REPORT_AGE_SECONDS
            );

        ctx.router.setRouteThrottle(workflowId, DISCOUNT_MIN_DELAY_SECONDS, DISCOUNT_MAX_STEP_BPS);
        console2.log("[OK] Discount-rate workflow route registered (throttle: 1 day, 100 bps; report age: 30 min)");
    }

    function _registerRiskParamsRoute(Context memory ctx) internal {
        bytes32 workflowId = vm.envBytes32("RISK_PARAMS_WORKFLOW_ID");
        bytes10 workflowName = bytes10(vm.envBytes32("RISK_PARAMS_WORKFLOW_NAME"));
        uint256 agentId = vm.envOr({ name: "EMODE_AGENT_ID", defaultValue: uint256(0) });

        console2.log("Registering risk-params workflow route...");
        console2.log("  workflowId:", uint256(workflowId));
        console2.log("  oracle:", ctx.riskOracle);

        ctx.router
            .addRoute(
                workflowId,
                ctx.forwarder,
                ctx.author,
                workflowName,
                ctx.riskOracle,
                RouterSelectors.PUBLISH_BULK_SELECTOR,
                agentId != 0 ? ctx.agentHub : address(0),
                _buildAgentIds(agentId, ctx.agentHub),
                MAX_REPORT_AGE_SECONDS
            );

        // Risk-params route: guard off (MAX_STEP_OFF) — tuple payload unaffected by frozen,
        // but explicit MAX_STEP_OFF documents intent
        ctx.router.setRouteThrottle(workflowId, 0, ctx.router.MAX_STEP_OFF());
        console2.log("[OK] Risk-params workflow route registered (throttle: guard off; report age: 30 min)");
    }
}
