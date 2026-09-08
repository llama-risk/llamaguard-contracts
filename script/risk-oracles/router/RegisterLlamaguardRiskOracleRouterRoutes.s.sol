// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { BaseScript } from "../Base.s.sol";
import { LlamaguardRiskOracleRouter } from "../../../src/LlamaguardRiskOracleRouter.sol";
import { IRiskOracle } from "aave-v3-risk-stewards/contracts/dependencies/IRiskOracle.sol";
import { ILlamaGuardOracle } from "llamaguard-contracts/src/interfaces/ILlamaGuardOracle.sol";
import { RouterSelectors } from "../RouterSelectors.sol";

/// @notice Post-deploy script that wires LlamaguardRiskOracleRouter with real CRE workflow IDs.
///         Run after `cre workflow deploy`, once workflow IDs are known.
///
///         IMPORTANT: Before running this script, ensure downstream oracles grant write access
///         to the router address:
///           - LlamaGuardOracle: grantRole(WRITER_ROLE, routerAddress)
///           - RiskOracle: addAuthorizedSender(routerAddress) or pass router in initialSenders
///         If these grants are missing, workflows will validate at the router but revert when
///         publishing. This script will emit warnings if permissions are missing, but will
///         continue to register routes (assuming permissions are granted in a separate step).
///
///         PUBLISH-ONLY MODE: Set AGENT_HUB_ADDRESS=0x0 to register routes without AgentHub
///         wiring. Workflows will publish to oracles but skip agent execution. This enables
///         staged rollouts: validate oracle updates first, then update routes to enable agents.
///
///         Required env vars:
///         - ROUTER_ADDRESS: deployed LlamaguardRiskOracleRouter
///         - RISK_ORACLE_ADDRESS: RiskOracle target for discount + risk-params routes
///         - LLAMAGUARD_ORACLE_ADDRESS: LlamaGuardOracle target for EMA route
///         - FORWARDER_ADDRESS: CRE forwarder for the target chain
///         - WORKFLOW_AUTHOR: workflow owner address
///         - EMA_WORKFLOW_ID: bytes32 workflow ID for pendle_ema_oracle
///         - EMA_WORKFLOW_NAME: bytes10 workflow name, provided as bytes32 hex
///         - DISCOUNT_WORKFLOW_ID: bytes32 workflow ID for pendle_discount_rate_oracle
///         - DISCOUNT_WORKFLOW_NAME: bytes10 workflow name, provided as bytes32 hex
///         - RISK_PARAMS_WORKFLOW_ID: bytes32 workflow ID for pendle_risk_parameters_oracle
///         - RISK_PARAMS_WORKFLOW_NAME: bytes10 workflow name, provided as bytes32 hex
///         - DISCOUNT_MIN_DELAY_SECONDS: discount-route minimum publish delay
///         - DISCOUNT_MAX_STEP_BPS: discount-route max-step cap, measured against the last
///           published value. `type(uint64).max` registers the route with the step guard off.
///
///         Optional env vars (for agent execution - omit for publish-only mode):
///         - AGENT_HUB_ADDRESS: AgentHub address for post-publish injection (default: 0x0)
///         - DISCOUNT_AGENT_ID: discount agent ID (required if AGENT_HUB_ADDRESS is set)
///         - EMODE_AGENT_ID: eMode agent ID (required if AGENT_HUB_ADDRESS is set)
///         - MAX_REPORT_AGE_SECONDS: replay-guard age bound for the discount + risk-params
///           routes (default 1800). The EMA route keeps the guard off: its LlamaGuardOracle
///           payload enforces its own deadline onchain.
contract RegisterLlamaguardRiskOracleRouterRoutes is BaseScript {
    /// @dev Default replay-guard age bound: 30 minutes. Sized above workflow execution plus
    ///      delivery latency and well below the 3h cron interval.
    uint64 internal constant DEFAULT_MAX_REPORT_AGE = 1800;

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
            agentHub: vm.envOr("AGENT_HUB_ADDRESS", address(0)),
            forwarder: vm.envAddress("FORWARDER_ADDRESS"),
            author: vm.envAddress("WORKFLOW_AUTHOR")
        });

        // Log publish-only mode if AgentHub is not configured
        if (ctx.agentHub == address(0)) {
            console2.log("");
            console2.log("=== PUBLISH-ONLY MODE ===");
            console2.log("AgentHub not configured. Routes will publish to oracles only.");
            console2.log("To enable agent execution later, use updateRoute() with AgentHub address.");
            console2.log("");
        }

        // Verify downstream write permissions before registering routes.
        // Emit warnings if missing (script continues; assume permissions granted separately).
        _verifyDownstreamPermissions(ctx);

        _registerEmaRoute(ctx);
        _registerDiscountRoute(ctx);
        _registerRiskParamsRoute(ctx);

        console2.log("All LlamaguardRiskOracleRouter workflow routes registered.");
    }

    /// @notice Verifies that the router has write access to downstream oracles.
    /// @dev Emits warnings if permissions are missing. Does not revert.
    function _verifyDownstreamPermissions(Context memory ctx) internal view {
        address routerAddr = address(ctx.router);
        bool allPermissionsGranted = true;

        // Check LlamaGuardOracle WRITER_ROLE for EMA route
        if (ctx.llamaGuardOracle != address(0)) {
            bool hasWriteAccess = ILlamaGuardOracle(ctx.llamaGuardOracle).hasWriteAccess(routerAddr);
            if (!hasWriteAccess) {
                console2.log("");
                console2.log("WARNING: Router does not have WRITER_ROLE on LlamaGuardOracle");
                console2.log("  Router:", routerAddr);
                console2.log("  LlamaGuardOracle:", ctx.llamaGuardOracle);
                console2.log("  Fix: LlamaGuardOracle.grantRole(WRITER_ROLE, router)");
                console2.log("");
                allPermissionsGranted = false;
            }
        }

        // Check RiskOracle authorized sender for discount/risk-params routes
        if (ctx.riskOracle != address(0)) {
            bool isAuthorized = IRiskOracle(ctx.riskOracle).isAuthorized(routerAddr);
            if (!isAuthorized) {
                console2.log("");
                console2.log("WARNING: Router is not an authorized sender on RiskOracle");
                console2.log("  Router:", routerAddr);
                console2.log("  RiskOracle:", ctx.riskOracle);
                console2.log("  Fix: RiskOracle.addAuthorizedSender(router)");
                console2.log("");
                allPermissionsGranted = false;
            }
        }

        if (allPermissionsGranted) {
            console2.log("[OK] Router has write access to all downstream oracles");
        } else {
            console2.log("!!! Missing permissions detected - workflows will revert when publishing");
            console2.log("!!! Grant permissions before activating workflows");
        }
    }

    function _buildAgentIds(uint256 agentId) internal pure returns (uint256[] memory) {
        uint256[] memory ids = new uint256[](1);
        ids[0] = agentId;
        return ids;
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
                // Replay guard off: the EMA workflow sends the bare LlamaGuardOracle payload.
                // Its onchain deadline (DeadlineExpired) bounds expiry only, not ordering, and
                // this route's selector is not one the router can decode, so enabling the guard
                // here would add no ordering even if the workflow enveloped. Tracked separately.
                0
            );

        // EMA route: guard off (MAX_STEP_OFF) — allow any delta between publishes.
        ctx.router.setRouteThrottle(workflowId, 0, ctx.router.MAX_STEP_OFF());
        console2.log("[OK] EMA workflow route registered (throttle: guard off)");
    }

    function _registerDiscountRoute(Context memory ctx) internal {
        bytes32 workflowId = vm.envBytes32("DISCOUNT_WORKFLOW_ID");
        bytes10 workflowName = bytes10(vm.envBytes32("DISCOUNT_WORKFLOW_NAME"));

        // Agent ID only required when AgentHub is configured
        uint256 agentId = vm.envOr("DISCOUNT_AGENT_ID", uint256(0));
        if (ctx.agentHub != address(0)) {
            require(agentId != 0, "DISCOUNT_AGENT_ID required when AGENT_HUB_ADDRESS is set");
        }

        console2.log("Registering discount-rate workflow route...");
        console2.log("  workflowId:", uint256(workflowId));
        console2.log("  oracle:", ctx.riskOracle);
        console2.log("  agentHub:", ctx.agentHub);

        // Pass empty agent IDs in publish-only mode
        uint256[] memory agentIds = ctx.agentHub != address(0) ? _buildAgentIds(agentId) : new uint256[](0);
        uint64 maxReportAgeSeconds = uint64(vm.envOr("MAX_REPORT_AGE_SECONDS", uint256(DEFAULT_MAX_REPORT_AGE)));

        ctx.router
            .addRoute(
                workflowId,
                ctx.forwarder,
                ctx.author,
                workflowName,
                ctx.riskOracle,
                RouterSelectors.PUBLISH_SINGLE_SELECTOR,
                ctx.agentHub,
                agentIds,
                maxReportAgeSeconds
            );

        uint64 minDelaySeconds = uint64(vm.envUint("DISCOUNT_MIN_DELAY_SECONDS"));
        uint64 maxStepBps = uint64(vm.envUint("DISCOUNT_MAX_STEP_BPS"));
        ctx.router.setRouteThrottle(workflowId, minDelaySeconds, maxStepBps);
        console2.log("[OK] Discount-rate workflow route registered");
        console2.log("  minDelaySeconds:", minDelaySeconds);
        console2.log("  maxStepBps:", maxStepBps);
        console2.log("  maxReportAgeSeconds:", maxReportAgeSeconds);
    }

    function _registerRiskParamsRoute(Context memory ctx) internal {
        bytes32 workflowId = vm.envBytes32("RISK_PARAMS_WORKFLOW_ID");
        bytes10 workflowName = bytes10(vm.envBytes32("RISK_PARAMS_WORKFLOW_NAME"));

        // Agent ID only required when AgentHub is configured
        uint256 agentId = vm.envOr("EMODE_AGENT_ID", uint256(0));
        if (ctx.agentHub != address(0)) {
            require(agentId != 0, "EMODE_AGENT_ID required when AGENT_HUB_ADDRESS is set");
        }

        console2.log("Registering risk-params workflow route...");
        console2.log("  workflowId:", uint256(workflowId));
        console2.log("  oracle:", ctx.riskOracle);
        console2.log("  agentHub:", ctx.agentHub);

        // Pass empty agent IDs in publish-only mode
        uint256[] memory agentIds = ctx.agentHub != address(0) ? _buildAgentIds(agentId) : new uint256[](0);
        uint64 maxReportAgeSeconds = uint64(vm.envOr("MAX_REPORT_AGE_SECONDS", uint256(DEFAULT_MAX_REPORT_AGE)));

        ctx.router
            .addRoute(
                workflowId,
                ctx.forwarder,
                ctx.author,
                workflowName,
                ctx.riskOracle,
                RouterSelectors.PUBLISH_BULK_SELECTOR,
                ctx.agentHub,
                agentIds,
                maxReportAgeSeconds
            );

        // Risk-params route: guard off (MAX_STEP_OFF) — tuple payload unaffected by frozen,
        // but explicit MAX_STEP_OFF documents intent and avoids confusion
        ctx.router.setRouteThrottle(workflowId, 0, ctx.router.MAX_STEP_OFF());
        console2.log("[OK] Risk-params workflow route registered (throttle: guard off)");
        console2.log("  maxReportAgeSeconds:", maxReportAgeSeconds);
    }
}
