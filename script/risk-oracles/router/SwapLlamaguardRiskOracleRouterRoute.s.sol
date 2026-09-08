// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { BaseScript } from "../Base.s.sol";
import { LlamaguardRiskOracleRouter } from "../../../src/LlamaguardRiskOracleRouter.sol";
import { IRiskOracle } from "aave-v3-risk-stewards/contracts/dependencies/IRiskOracle.sol";
import { ILlamaGuardOracle } from "llamaguard-contracts/src/interfaces/ILlamaGuardOracle.sol";
import { RouterSelectors } from "../RouterSelectors.sol";

/// @notice Redeploy swap: register a route for a freshly-redeployed CRE workflow and remove the old
///         route it replaces. A workflow's on-chain ID is a hash of its WASM+config, so any code
///         change produces a NEW workflow ID. Router routes are keyed by workflowId, so the new
///         workflow's reports revert with RouteNotFound until a route for the new ID exists, and the
///         old route lingers dead-but-registered. This script does both sides of the swap in a single
///         broadcast (there is never a window with neither route present):
///           1. addRoute(NEW_WORKFLOW_ID, ...same settings as the old route...)
///           2. removeRoute(OLD_WORKFLOW_ID)
///
///         The new route mirrors the original registration exactly (same forwarder, author, bytes10
///         workflow name, downstream oracle, and publish selector). The workflow name is unchanged
///         across a redeploy, so "same settings" holds; only the workflowId key changes.
///
///         Both addRoute and removeRoute are onlyOwner on the router. The broadcaster must be the
///         router owner.
///
///         PUBLISH-ONLY MODE: leave AGENT_HUB_ADDRESS empty/zero to swap a route without AgentHub
///         wiring (matches the current Plasma shadow deployment).
///
///         Required env vars:
///         - ROUTER_ADDRESS: deployed LlamaguardRiskOracleRouter
///         - WORKFLOW_KIND: one of "ema", "discount", "risk" (selects oracle + publish selector)
///         - NEW_WORKFLOW_ID: bytes32 workflow ID from the redeploy
///         - OLD_WORKFLOW_ID: bytes32 workflow ID currently routed (to be removed)
///         - WORKFLOW_NAME: bytes10 workflow name, provided as bytes32 hex (unchanged across redeploy)
///         - FORWARDER_ADDRESS: CRE forwarder for the target chain
///         - WORKFLOW_AUTHOR: workflow owner address
///         - RISK_ORACLE_ADDRESS: RiskOracle target (required for "discount"/"risk")
///         - LLAMAGUARD_ORACLE_ADDRESS: LlamaGuardOracle target (required for "ema")
///         - DISCOUNT_MIN_DELAY_SECONDS: current discount-route delay (required for "discount")
///         - DISCOUNT_MAX_STEP_BPS: current discount-route max-step cap (required for "discount"),
///           `type(uint64).max` if the step guard is off
///
///         Optional env vars (for agent execution - omit for publish-only mode):
///         - AGENT_HUB_ADDRESS: AgentHub address for post-publish injection (default: 0x0)
///         - DISCOUNT_AGENT_ID: discount agent ID (required for "discount" if AGENT_HUB_ADDRESS is set)
///         - EMODE_AGENT_ID: eMode agent ID (required for "risk" if AGENT_HUB_ADDRESS is set)
///         - MAX_REPORT_AGE_SECONDS: replay-guard age bound for "discount"/"risk" routes
///           (default 1800; "ema" always keeps the guard off)
contract SwapLlamaguardRiskOracleRouterRoute is BaseScript {
    function run() public broadcast {
        LlamaguardRiskOracleRouter router = LlamaguardRiskOracleRouter(vm.envAddress("ROUTER_ADDRESS"));
        string memory kind = vm.envString("WORKFLOW_KIND");
        bytes32 newWorkflowId = vm.envBytes32("NEW_WORKFLOW_ID");
        bytes32 oldWorkflowId = vm.envBytes32("OLD_WORKFLOW_ID");
        bytes10 workflowName = bytes10(vm.envBytes32("WORKFLOW_NAME"));
        address forwarder = vm.envAddress("FORWARDER_ADDRESS");
        address author = vm.envAddress("WORKFLOW_AUTHOR");
        address agentHub = vm.envOr("AGENT_HUB_ADDRESS", address(0));

        require(newWorkflowId != oldWorkflowId, "NEW_WORKFLOW_ID must differ from OLD_WORKFLOW_ID");
        require(newWorkflowId != bytes32(0), "NEW_WORKFLOW_ID is required");
        require(oldWorkflowId != bytes32(0), "OLD_WORKFLOW_ID is required");

        // Resolve the downstream oracle, publish selector, and agent wiring from the workflow kind,
        // exactly as RegisterLlamaguardRiskOracleRouterRoutes does per workflow.
        (address oracle, bytes4 selector, uint256[] memory agentIds) = _resolveRoute(kind, agentHub);

        _verifyDownstreamPermissions(router, kind);

        if (agentHub == address(0)) {
            console2.log("");
            console2.log("=== PUBLISH-ONLY MODE ===");
            console2.log("AgentHub not configured. New route will publish to the oracle only.");
            console2.log("");
        }

        console2.log("=== Swapping workflow route ===");
        console2.log("  kind:            ", kind);
        console2.log("  new workflowId:  ", uint256(newWorkflowId));
        console2.log("  old workflowId:  ", uint256(oldWorkflowId));
        console2.log("  forwarder:       ", forwarder);
        console2.log("  author:          ", author);
        console2.log("  oracle:          ", oracle);
        console2.log("  agentHub:        ", agentHub);

        // 1. Register the new route first so no report is ever dropped mid-swap. The replay
        //    guard is set in the same call: RiskOracle routes (discount, risk) require the
        //    signed-timestamp envelope; the EMA route sends the bare LlamaGuardOracle payload,
        //    which enforces its own deadline onchain, so the guard stays off there.
        uint64 maxReportAgeSeconds = _resolveMaxReportAge(kind);
        router.addRoute(
            newWorkflowId, forwarder, author, workflowName, oracle, selector, agentHub, agentIds, maxReportAgeSeconds
        );

        // 2. Preserve throttle intent across workflow-ID rotation. EMA and risk use the explicit
        //    off sentinel; discount retains its configured delay and relative cap.
        (uint64 minDelaySeconds, uint64 maxStepBps) = _resolveThrottle(router, kind);
        router.setRouteThrottle(newWorkflowId, minDelaySeconds, maxStepBps);
        console2.log("[OK] New route registered for redeployed workflow");
        console2.log("  minDelaySeconds:", minDelaySeconds);
        console2.log("  maxStepBps:", maxStepBps);
        console2.log("  maxReportAgeSeconds:", maxReportAgeSeconds);

        // 3. Remove the stale route the redeploy replaces.
        router.removeRoute(oldWorkflowId);
        console2.log("[OK] Old route removed");

        console2.log("Route swap complete.");
    }

    function _resolveThrottle(
        LlamaguardRiskOracleRouter router,
        string memory kind
    )
        internal
        view
        returns (uint64 minDelaySeconds, uint64 maxStepBps)
    {
        if (keccak256(bytes(kind)) == keccak256("discount")) {
            return (uint64(vm.envUint("DISCOUNT_MIN_DELAY_SECONDS")), uint64(vm.envUint("DISCOUNT_MAX_STEP_BPS")));
        }
        return (0, router.MAX_STEP_OFF());
    }

    /// @dev Replay-guard age bound per workflow kind: off for "ema", MAX_REPORT_AGE_SECONDS
    ///      (default 1800) for the RiskOracle routes.
    function _resolveMaxReportAge(string memory kind) internal view returns (uint64) {
        if (keccak256(bytes(kind)) == keccak256("ema")) {
            return 0;
        }
        return uint64(vm.envOr("MAX_REPORT_AGE_SECONDS", uint256(1800)));
    }

    /// @dev Maps WORKFLOW_KIND to (downstream oracle, publish selector, agentIds), mirroring the
    ///      per-workflow route shapes in RegisterLlamaguardRiskOracleRouterRoutes.
    function _resolveRoute(
        string memory kind,
        address agentHub
    )
        internal
        view
        returns (address oracle, bytes4 selector, uint256[] memory agentIds)
    {
        bytes32 kindHash = keccak256(bytes(kind));

        if (kindHash == keccak256("ema")) {
            // The EMA route never uses AgentHub (matches the register script).
            oracle = vm.envAddress("LLAMAGUARD_ORACLE_ADDRESS");
            selector = RouterSelectors.UPDATE_LLAMAGUARD_SELECTOR;
            agentIds = new uint256[](0);
        } else if (kindHash == keccak256("discount")) {
            oracle = vm.envAddress("RISK_ORACLE_ADDRESS");
            selector = RouterSelectors.PUBLISH_SINGLE_SELECTOR;
            agentIds = _agentIds(agentHub, "DISCOUNT_AGENT_ID");
        } else if (kindHash == keccak256("risk")) {
            oracle = vm.envAddress("RISK_ORACLE_ADDRESS");
            selector = RouterSelectors.PUBLISH_BULK_SELECTOR;
            agentIds = _agentIds(agentHub, "EMODE_AGENT_ID");
        } else {
            revert("WORKFLOW_KIND must be one of: ema, discount, risk");
        }
    }

    /// @dev Publish-only mode passes an empty agentIds set; full mode requires the agent ID.
    function _agentIds(address agentHub, string memory agentIdEnv) internal view returns (uint256[] memory) {
        if (agentHub == address(0)) return new uint256[](0);
        uint256 agentId = vm.envOr(agentIdEnv, uint256(0));
        require(agentId != 0, string.concat(agentIdEnv, " required when AGENT_HUB_ADDRESS is set"));
        uint256[] memory ids = new uint256[](1);
        ids[0] = agentId;
        return ids;
    }

    /// @notice Verifies the router still has write access to the downstream oracle for this kind.
    /// @dev Warn-only; does not revert. The swap does not change permissions, so this should already
    ///      be satisfied from the original deployment.
    function _verifyDownstreamPermissions(LlamaguardRiskOracleRouter router, string memory kind) internal view {
        address routerAddr = address(router);
        bytes32 kindHash = keccak256(bytes(kind));

        if (kindHash == keccak256("ema")) {
            address llamaGuardOracle = vm.envAddress("LLAMAGUARD_ORACLE_ADDRESS");
            if (!ILlamaGuardOracle(llamaGuardOracle).hasWriteAccess(routerAddr)) {
                console2.log("");
                console2.log("WARNING: Router does not have WRITER_ROLE on LlamaGuardOracle");
                console2.log("  Router:", routerAddr);
                console2.log("  LlamaGuardOracle:", llamaGuardOracle);
                console2.log("  Fix: LlamaGuardOracle.grantRole(WRITER_ROLE, router)");
                console2.log("");
            } else {
                console2.log("[OK] Router has write access to LlamaGuardOracle");
            }
        } else {
            address riskOracle = vm.envAddress("RISK_ORACLE_ADDRESS");
            if (!IRiskOracle(riskOracle).isAuthorized(routerAddr)) {
                console2.log("");
                console2.log("WARNING: Router is not an authorized sender on RiskOracle");
                console2.log("  Router:", routerAddr);
                console2.log("  RiskOracle:", riskOracle);
                console2.log("  Fix: RiskOracle.addAuthorizedSender(router)");
                console2.log("");
            } else {
                console2.log("[OK] Router is an authorized sender on RiskOracle");
            }
        }
    }
}
