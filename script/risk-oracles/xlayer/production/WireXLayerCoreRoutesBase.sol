// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { Script } from "forge-std/Script.sol";
import { LlamaguardRiskOracleRouter } from "../../../../src/LlamaguardRiskOracleRouter.sol";
import { IAgentHub } from "chaos-agents/interfaces/IAgentHub.sol";
import { IRangeValidationModule } from "chaos-agents/interfaces/IRangeValidationModule.sol";
import { IACLManager } from "aave-address-book/AaveV3.sol";
import { RouterSelectors } from "../../RouterSelectors.sol";
import { XLayerCoreConfig } from "./XLayerCoreConfig.sol";
import { XLayerCoreDeployed } from "./XLayerCoreDeployed.sol";
import { XLayerCoreExternalAddresses } from "./XLayerCoreExternalAddresses.sol";
import { PTUSDG25FEB2027 } from "./assets/PTUSDG25FEB2027.sol";
import { SafeTx } from "../../ethereum/production/SafeTx.sol";

/// @title WireXLayerCoreRoutesBase
/// @notice What both halves of phase 3 share. Broadcasts nothing: each phase prints its batch and
///         the safe executes it. Mirror of `WireEthereumCoreRoutesBase`, which documents the
///         reasoning (batch shape, throttle pairing, name derivation).
abstract contract WireXLayerCoreRoutesBase is Script {
    struct Context {
        address router;
        address riskOracle;
        address emaOracle;
        address agentHub;
        uint256 discountAgentId;
        uint256 emodeAgentId;
        address discountAgent;
        address emodeAgent;
        bytes32 emaWorkflowId;
        bytes32 discountWorkflowId;
        bytes32 riskParamsWorkflowId;
    }

    struct Workflow {
        bytes32 id;
        bytes10 name;
    }

    function emaCallsFromDeployed() public pure returns (SafeTx.Call[] memory) {
        return emaCalls(_emaContext());
    }

    /// @notice The EMA route: no agent hub, no agent ids, bare payload (`maxReportAgeSeconds` 0).
    function emaCalls(Context memory ctx) public pure returns (SafeTx.Call[] memory calls) {
        calls = new SafeTx.Call[](2);

        Workflow memory ema = _workflow(ctx.emaWorkflowId, PTUSDG25FEB2027.EMA_WORKFLOW_NAME);

        calls[0] = SafeTx.call(
            "router.addRoute(EMA)",
            ctx.router,
            abi.encodeCall(
                LlamaguardRiskOracleRouter.addRoute,
                (
                    ema.id,
                    XLayerCoreExternalAddresses.CRE_FORWARDER,
                    XLayerCoreExternalAddresses.CRE_WORKFLOW_OWNER,
                    ema.name,
                    ctx.emaOracle,
                    RouterSelectors.UPDATE_LLAMAGUARD_SELECTOR,
                    address(0),
                    new uint256[](0),
                    0
                )
            )
        );
        calls[1] = SafeTx.call(
            "router.setRouteThrottle(EMA, 0, MAX_STEP_OFF)",
            ctx.router,
            abi.encodeCall(
                LlamaguardRiskOracleRouter.setRouteThrottle, (ema.id, 0, XLayerCoreConfig.ROUTER_MAX_STEP_OFF)
            )
        );
    }

    /// @notice The discount and risk-params routes; both inject through the AgentHub.
    function agentCalls(Context memory ctx) public pure returns (SafeTx.Call[] memory calls) {
        calls = new SafeTx.Call[](4);

        Workflow memory discount = _workflow(ctx.discountWorkflowId, PTUSDG25FEB2027.DISCOUNT_WORKFLOW_NAME);
        Workflow memory riskParams = _workflow(ctx.riskParamsWorkflowId, PTUSDG25FEB2027.RISK_PARAMS_WORKFLOW_NAME);

        calls[0] = SafeTx.call(
            "router.addRoute(discount)",
            ctx.router,
            abi.encodeCall(
                LlamaguardRiskOracleRouter.addRoute,
                (
                    discount.id,
                    XLayerCoreExternalAddresses.CRE_FORWARDER,
                    XLayerCoreExternalAddresses.CRE_WORKFLOW_OWNER,
                    discount.name,
                    ctx.riskOracle,
                    RouterSelectors.PUBLISH_SINGLE_SELECTOR,
                    ctx.agentHub,
                    _singleton(ctx.discountAgentId),
                    XLayerCoreConfig.MAX_REPORT_AGE_SECONDS
                )
            )
        );
        calls[1] = SafeTx.call(
            "router.setRouteThrottle(discount, 48h, MAX_STEP_OFF)",
            ctx.router,
            abi.encodeCall(
                LlamaguardRiskOracleRouter.setRouteThrottle,
                (discount.id, PTUSDG25FEB2027.DISCOUNT_MIN_DELAY_SECONDS, PTUSDG25FEB2027.DISCOUNT_ROUTER_MAX_STEP)
            )
        );

        // Tuple payloads cannot be step capped; freezing this route means setRouteEnabled(false).
        calls[2] = SafeTx.call(
            "router.addRoute(riskParams)",
            ctx.router,
            abi.encodeCall(
                LlamaguardRiskOracleRouter.addRoute,
                (
                    riskParams.id,
                    XLayerCoreExternalAddresses.CRE_FORWARDER,
                    XLayerCoreExternalAddresses.CRE_WORKFLOW_OWNER,
                    riskParams.name,
                    ctx.riskOracle,
                    RouterSelectors.PUBLISH_BULK_SELECTOR,
                    ctx.agentHub,
                    _singleton(ctx.emodeAgentId),
                    XLayerCoreConfig.MAX_REPORT_AGE_SECONDS
                )
            )
        );
        calls[3] = SafeTx.call(
            "router.setRouteThrottle(riskParams, 0, MAX_STEP_OFF)",
            ctx.router,
            abi.encodeCall(
                LlamaguardRiskOracleRouter.setRouteThrottle, (riskParams.id, 0, XLayerCoreConfig.ROUTER_MAX_STEP_OFF)
            )
        );
    }

    /// @dev Deliberately reads no agent ids: they are unset until the AIP executes.
    function _emaContext() internal pure returns (Context memory ctx) {
        ctx.router = XLayerCoreDeployed.ROUTER;
        ctx.emaOracle = XLayerCoreDeployed.EMA_ORACLE_PT_USDG_25FEB2027;
        ctx.emaWorkflowId = XLayerCoreDeployed.EMA_WORKFLOW_ID;

        require(ctx.router != address(0), "WireXLayerCoreRoutes: XLayerCoreDeployed.ROUTER unset");
        require(ctx.emaOracle != address(0), "WireXLayerCoreRoutes: XLayerCoreDeployed EMA oracle unset");
        require(ctx.emaWorkflowId != bytes32(0), "WireXLayerCoreRoutes: XLayerCoreDeployed.EMA_WORKFLOW_ID unset");
    }

    function _context() internal pure returns (Context memory ctx) {
        ctx = Context({
            router: XLayerCoreDeployed.ROUTER,
            riskOracle: XLayerCoreDeployed.RISK_ORACLE,
            emaOracle: XLayerCoreDeployed.EMA_ORACLE_PT_USDG_25FEB2027,
            agentHub: XLayerCoreExternalAddresses.AGENT_HUB,
            discountAgentId: XLayerCoreDeployed.DISCOUNT_AGENT_ID,
            emodeAgentId: XLayerCoreDeployed.EMODE_AGENT_ID,
            discountAgent: XLayerCoreDeployed.DISCOUNT_RATE_AGENT,
            emodeAgent: XLayerCoreDeployed.EMODE_AGENT,
            emaWorkflowId: XLayerCoreDeployed.EMA_WORKFLOW_ID,
            discountWorkflowId: XLayerCoreDeployed.DISCOUNT_WORKFLOW_ID,
            riskParamsWorkflowId: XLayerCoreDeployed.RISK_PARAMS_WORKFLOW_ID
        });

        require(ctx.router != address(0), "WireXLayerCoreRoutes: XLayerCoreDeployed.ROUTER unset");
        require(ctx.riskOracle != address(0), "WireXLayerCoreRoutes: XLayerCoreDeployed.RISK_ORACLE unset");
        require(ctx.emaOracle != address(0), "WireXLayerCoreRoutes: XLayerCoreDeployed EMA oracle unset");
        require(
            ctx.discountAgentId != XLayerCoreConfig.AGENT_ID_UNSET,
            "WireXLayerCoreRoutes: XLayerCoreDeployed.DISCOUNT_AGENT_ID unset"
        );
        require(
            ctx.emodeAgentId != XLayerCoreConfig.AGENT_ID_UNSET,
            "WireXLayerCoreRoutes: XLayerCoreDeployed.EMODE_AGENT_ID unset"
        );
    }

    /// @notice Everything the AIP was supposed to leave behind, checked onchain.
    /// @dev    On Ethereum and Plasma this was a precondition of wiring the agent routes. X Layer
    ///         wires every route up front (see `3_WireRoutes`), so this cannot gate the batch — the
    ///         AIP does not exist yet when it runs. It is kept, and kept public, as the post-AIP
    ///         verification: run it once the proposal executes to confirm the payload did what it
    ///         claimed, because from then on a wrong payload fails silently.
    function requireTheAipLanded(Context memory ctx) public view {
        _requireAgentLanded(ctx, ctx.discountAgentId, ctx.discountAgent, XLayerCoreConfig.TYPE_DISCOUNT, "discount");
        _requireAgentLanded(ctx, ctx.emodeAgentId, ctx.emodeAgent, XLayerCoreConfig.TYPE_EMODE, "eMode");

        _requireRangeConfigured(ctx.discountAgentId, XLayerCoreConfig.TYPE_DISCOUNT);
        _requireRangeConfigured(ctx.emodeAgentId, "EModeLTV");
        _requireRangeConfigured(ctx.emodeAgentId, "EModeLiquidationThreshold");
        _requireRangeConfigured(ctx.emodeAgentId, "EModeLiquidationBonus");
    }

    function _requireAgentLanded(
        Context memory ctx,
        uint256 agentId,
        address expectedAgent,
        string memory expectedUpdateType,
        string memory label
    )
        internal
        view
    {
        IAgentHub hub = IAgentHub(ctx.agentHub);

        require(expectedAgent != address(0), string.concat("WireXLayerCoreRoutes: ", label, " agent address unset"));
        require(
            hub.getAgentAddress(agentId) == expectedAgent,
            string.concat("WireXLayerCoreRoutes: id is not the ", label, " agent")
        );
        require(
            hub.isAgentEnabled(agentId),
            string.concat("WireXLayerCoreRoutes: ", label, " agent registered but disabled")
        );
        require(
            hub.getRiskOracle(agentId) == ctx.riskOracle,
            string.concat("WireXLayerCoreRoutes: ", label, " agent points at another RiskOracle")
        );
        require(
            keccak256(bytes(hub.getUpdateType(agentId))) == keccak256(bytes(expectedUpdateType)),
            string.concat("WireXLayerCoreRoutes: ", label, " agent listens for another update type")
        );
        require(
            IACLManager(XLayerCoreExternalAddresses.AAVE_ACL_MANAGER).isRiskAdmin(expectedAgent),
            string.concat("WireXLayerCoreRoutes: ", label, " agent is not a RISK_ADMIN")
        );
    }

    function _requireRangeConfigured(uint256 agentId, string memory updateType) internal view {
        IRangeValidationModule module = IRangeValidationModule(XLayerCoreExternalAddresses.RANGE_VALIDATION_MODULE);
        IRangeValidationModule.RangeConfig memory config =
            module.getDefaultRangeConfig(XLayerCoreExternalAddresses.AGENT_HUB, agentId, updateType);

        require(
            config.maxIncrease != 0 || config.maxDecrease != 0,
            string.concat("WireXLayerCoreRoutes: no range config for ", updateType)
        );
    }

    function _workflow(bytes32 id, string memory name) internal pure returns (Workflow memory) {
        require(id != bytes32(0), string.concat("WireXLayerCoreRoutes: workflow id unset for ", name));
        return Workflow({ id: id, name: creWorkflowName(name) });
    }

    function _singleton(uint256 value) internal pure returns (uint256[] memory out) {
        out = new uint256[](1);
        out[0] = value;
    }

    /// @notice `bytes10` route name: sha256 the workflow name, hex encode, keep the first ten hex
    ///         characters as ASCII. The raw name is NEVER the answer.
    function creWorkflowName(string memory workflowName) public pure returns (bytes10) {
        require(bytes(workflowName).length != 0, "WireXLayerCoreRoutes: empty workflow name");

        bytes32 digest = sha256(bytes(workflowName));
        bytes memory hexChars = "0123456789abcdef";
        bytes memory result = new bytes(10);
        for (uint256 i = 0; i < 5; i++) {
            uint8 b = uint8(digest[i]);
            result[i * 2] = hexChars[b >> 4];
            result[i * 2 + 1] = hexChars[b & 0x0f];
        }
        return bytes10(result);
    }
}
