// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { LlamaguardRiskOracleRouter } from "../../../../src/LlamaguardRiskOracleRouter.sol";
import { IAgentHub } from "chaos-agents/interfaces/IAgentHub.sol";
import { IRangeValidationModule } from "chaos-agents/interfaces/IRangeValidationModule.sol";
import { IACLManager } from "aave-address-book/AaveV3.sol";
import { RouterSelectors } from "../../RouterSelectors.sol";
import { EthereumCoreConfig } from "./EthereumCoreConfig.sol";
import { EthereumCoreDeployed } from "./EthereumCoreDeployed.sol";
import { EthereumCoreExternalAddresses } from "./EthereumCoreExternalAddresses.sol";
import { PTsrUSDe22OCT2026 } from "./assets/PTsrUSDe22OCT2026.sol";
import { SafeTx } from "./SafeTx.sol";

/// @title WireEthereumCoreRoutesBase
/// @notice What both halves of phase 3 share: the context, the call builders, the AIP checks and
///         the workflow-name derivation.
/// @dev    **Broadcasts nothing.** By the time phase 3 runs the safe has accepted the Router, so
///         `addRoute` is `onlyOwner` and `setRouteThrottle` is `onlyUpdater` on an owner no key here
///         holds. Each phase prints its batch; the safe executes it.
///
///         Both calls per route go in one batch because owner and updater are the same safe. They
///         are not independently optional: `addRoute` leaves `maxStepBps` at 0, which for a scalar
///         payload means frozen, not unguarded. A route registered without its throttle rejects
///         every publish that changes the value.
abstract contract WireEthereumCoreRoutesBase is Script {
    struct Context {
        address router;
        address riskOracle;
        address emaOracle;
        address agentHub;
        uint256 discountAgentId;
        uint256 emodeAgentId;
        /// @dev The agent contracts the AIP deployed. Carried here rather than read from
        ///      `EthereumCoreDeployed` inside the checks, for the same reason the workflow ids are:
        ///      a verification that reads its own expectations from a committed constant cannot be
        ///      driven against a stack that constant does not name.
        address discountAgent;
        address emodeAgent;
        /// @dev The three workflow ids `cre workflow deploy` minted. Carried in the context rather
        ///      than read from `EthereumCoreDeployed` inside `routeCalls`, so the fork test can
        ///      build the same batch against ids that do not exist yet.
        bytes32 emaWorkflowId;
        bytes32 discountWorkflowId;
        bytes32 riskParamsWorkflowId;
    }

    struct Workflow {
        bytes32 id;
        bytes10 name;
    }

    /// @notice The EMA calls built from the recorded deployment, for the fork test.
    function emaCallsFromDeployed() public pure returns (SafeTx.Call[] memory) {
        return emaCalls(_emaContext());
    }

    /// @notice The EMA route, as data. Needs no agent id and no AgentHub.
    function emaCalls(Context memory ctx) public pure returns (SafeTx.Call[] memory calls) {
        calls = new SafeTx.Call[](2);

        Workflow memory ema = _workflow(ctx.emaWorkflowId, PTsrUSDe22OCT2026.EMA_WORKFLOW_NAME);

        // The EMA route writes to the per-asset LlamaGuardOracle rather than to the RiskOracle, so
        // it carries no agent hub and no agent ids. `maxReportAgeSeconds` is 0, which registers it
        // for the bare payload rather than the signed-timestamp envelope.
        calls[0] = SafeTx.call(
            "router.addRoute(EMA)",
            ctx.router,
            abi.encodeCall(
                LlamaguardRiskOracleRouter.addRoute,
                (
                    ema.id,
                    EthereumCoreExternalAddresses.CRE_FORWARDER,
                    EthereumCoreExternalAddresses.CRE_WORKFLOW_OWNER,
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
                LlamaguardRiskOracleRouter.setRouteThrottle, (ema.id, 0, EthereumCoreConfig.ROUTER_MAX_STEP_OFF)
            )
        );
    }

    /// @notice The discount and risk-params routes, as data. Both inject through the AgentHub, so
    ///         both carry an agent id the AIP assigned.
    function agentCalls(Context memory ctx) public pure returns (SafeTx.Call[] memory calls) {
        calls = new SafeTx.Call[](4);

        Workflow memory discount = _workflow(ctx.discountWorkflowId, PTsrUSDe22OCT2026.DISCOUNT_WORKFLOW_NAME);
        Workflow memory riskParams = _workflow(ctx.riskParamsWorkflowId, PTsrUSDe22OCT2026.RISK_PARAMS_WORKFLOW_NAME);

        // The discount route is the only one the Router can rate limit meaningfully: its payload is
        // a 32-byte scalar, so both the min delay and the step cap apply.
        calls[0] = SafeTx.call(
            "router.addRoute(discount)",
            ctx.router,
            abi.encodeCall(
                LlamaguardRiskOracleRouter.addRoute,
                (
                    discount.id,
                    EthereumCoreExternalAddresses.CRE_FORWARDER,
                    EthereumCoreExternalAddresses.CRE_WORKFLOW_OWNER,
                    discount.name,
                    ctx.riskOracle,
                    RouterSelectors.PUBLISH_SINGLE_SELECTOR,
                    ctx.agentHub,
                    _singleton(ctx.discountAgentId),
                    EthereumCoreConfig.MAX_REPORT_AGE_SECONDS
                )
            )
        );
        calls[1] = SafeTx.call(
            "router.setRouteThrottle(discount, 48h, MAX_STEP_OFF)",
            ctx.router,
            abi.encodeCall(
                LlamaguardRiskOracleRouter.setRouteThrottle,
                (discount.id, PTsrUSDe22OCT2026.DISCOUNT_MIN_DELAY_SECONDS, PTsrUSDe22OCT2026.DISCOUNT_ROUTER_MAX_STEP)
            )
        );

        // The risk-params route publishes tuples, which the Router cannot decode, so the step guard
        // is expressed as off rather than as a number that would silently never apply. Freezing
        // this route means `setRouteEnabled(false)`.
        calls[2] = SafeTx.call(
            "router.addRoute(riskParams)",
            ctx.router,
            abi.encodeCall(
                LlamaguardRiskOracleRouter.addRoute,
                (
                    riskParams.id,
                    EthereumCoreExternalAddresses.CRE_FORWARDER,
                    EthereumCoreExternalAddresses.CRE_WORKFLOW_OWNER,
                    riskParams.name,
                    ctx.riskOracle,
                    RouterSelectors.PUBLISH_BULK_SELECTOR,
                    ctx.agentHub,
                    _singleton(ctx.emodeAgentId),
                    EthereumCoreConfig.MAX_REPORT_AGE_SECONDS
                )
            )
        );
        calls[3] = SafeTx.call(
            "router.setRouteThrottle(riskParams, 0, MAX_STEP_OFF)",
            ctx.router,
            abi.encodeCall(
                LlamaguardRiskOracleRouter.setRouteThrottle, (riskParams.id, 0, EthereumCoreConfig.ROUTER_MAX_STEP_OFF)
            )
        );
    }

    /// @notice What the EMA route needs, and nothing more.
    /// @dev    Deliberately does not read or check the agent ids. They are unset until the AIP
    ///         executes, and `_context` rejects that, which would otherwise block a route that has
    ///         no agent in it.
    function _emaContext() internal pure returns (Context memory ctx) {
        ctx.router = EthereumCoreDeployed.ROUTER;
        ctx.emaOracle = EthereumCoreDeployed.EMA_ORACLE_PT_SRUSDE_22OCT2026;
        ctx.emaWorkflowId = EthereumCoreDeployed.EMA_WORKFLOW_ID;

        require(ctx.router != address(0), "WireEthereumCoreRoutes: EthereumCoreDeployed.ROUTER unset");
        require(ctx.emaOracle != address(0), "WireEthereumCoreRoutes: EthereumCoreDeployed EMA oracle unset");
        require(ctx.emaWorkflowId != bytes32(0), "WireEthereumCoreRoutes: EthereumCoreDeployed.EMA_WORKFLOW_ID unset");
    }

    /// @notice Everything phase 3 needs, read from the recorded deployment rather than from env.
    function _context() internal pure returns (Context memory ctx) {
        ctx = Context({
            router: EthereumCoreDeployed.ROUTER,
            riskOracle: EthereumCoreDeployed.RISK_ORACLE,
            emaOracle: EthereumCoreDeployed.EMA_ORACLE_PT_SRUSDE_22OCT2026,
            agentHub: EthereumCoreExternalAddresses.AGENT_HUB,
            discountAgentId: EthereumCoreDeployed.DISCOUNT_AGENT_ID,
            emodeAgentId: EthereumCoreDeployed.EMODE_AGENT_ID,
            discountAgent: EthereumCoreDeployed.DISCOUNT_RATE_AGENT,
            emodeAgent: EthereumCoreDeployed.EMODE_AGENT,
            emaWorkflowId: EthereumCoreDeployed.EMA_WORKFLOW_ID,
            discountWorkflowId: EthereumCoreDeployed.DISCOUNT_WORKFLOW_ID,
            riskParamsWorkflowId: EthereumCoreDeployed.RISK_PARAMS_WORKFLOW_ID
        });

        require(ctx.router != address(0), "WireEthereumCoreRoutes: EthereumCoreDeployed.ROUTER unset");
        require(ctx.riskOracle != address(0), "WireEthereumCoreRoutes: EthereumCoreDeployed.RISK_ORACLE unset");
        require(ctx.emaOracle != address(0), "WireEthereumCoreRoutes: EthereumCoreDeployed EMA oracle unset");
        require(
            ctx.discountAgentId != EthereumCoreConfig.AGENT_ID_UNSET,
            "WireEthereumCoreRoutes: EthereumCoreDeployed.DISCOUNT_AGENT_ID unset"
        );
        require(
            ctx.emodeAgentId != EthereumCoreConfig.AGENT_ID_UNSET,
            "WireEthereumCoreRoutes: EthereumCoreDeployed.EMODE_AGENT_ID unset"
        );
    }

    /// @notice Everything the AIP was supposed to leave behind, checked against the chain before a
    ///         single route is wired.
    /// @dev    This is the last gate. After phase 3 the stack is live, and every way the payload can
    ///         be wrong fails silently rather than loudly: a missing `RISK_ADMIN` grant, an unset
    ///         range config or a swapped id all produce a route that publishes happily and injects
    ///         nothing, because the Router catches AgentHub failures by design so a bad injection
    ///         cannot roll back a good publish.
    ///
    ///         Every check below is a read, so this costs nothing and runs before the batch is even
    ///         printed. Agent id 0 is a legitimate hub id, so an unset id cannot be caught by
    ///         comparing against zero, which is why the identity check is against the recorded
    ///         address rather than against the number.
    function requireTheAipLanded(Context memory ctx) public view {
        _requireAgentLanded(ctx, ctx.discountAgentId, ctx.discountAgent, EthereumCoreConfig.TYPE_DISCOUNT, "discount");
        _requireAgentLanded(ctx, ctx.emodeAgentId, ctx.emodeAgent, EthereumCoreConfig.TYPE_EMODE, "eMode");

        // A fresh agent id inherits no default range config, and the module reads a missing one as a
        // zero bound, so an unset range is not a loose stack, it is a dead one.
        _requireRangeConfigured(ctx.discountAgentId, EthereumCoreConfig.TYPE_DISCOUNT);
        _requireRangeConfigured(ctx.emodeAgentId, "EModeLTV");
        _requireRangeConfigured(ctx.emodeAgentId, "EModeLiquidationThreshold");
        _requireRangeConfigured(ctx.emodeAgentId, "EModeLiquidationBonus");
    }

    /// @dev Four facts per agent, all of them the payload's to get right and none of them visible
    ///      from a block explorer at a glance.
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

        require(expectedAgent != address(0), string.concat("WireEthereumCoreRoutes: ", label, " agent address unset"));
        // Catches the two ids being transcribed the wrong way round.
        require(
            hub.getAgentAddress(agentId) == expectedAgent,
            string.concat("WireEthereumCoreRoutes: id is not the ", label, " agent")
        );
        require(
            hub.isAgentEnabled(agentId),
            string.concat("WireEthereumCoreRoutes: ", label, " agent registered but disabled")
        );
        // A registration pointing at a different RiskOracle would never see our records at all.
        require(
            hub.getRiskOracle(agentId) == ctx.riskOracle,
            string.concat("WireEthereumCoreRoutes: ", label, " agent points at another RiskOracle")
        );
        // The agents are the payload's to construct, so the empty `updateTypeSuffix` is an assumption
        // on our side until it is read back. A suffixed agent simply never matches a record.
        require(
            keccak256(bytes(hub.getUpdateType(agentId))) == keccak256(bytes(expectedUpdateType)),
            string.concat("WireEthereumCoreRoutes: ", label, " agent listens for another update type")
        );
        // The grant is the item most easily dropped from a payload, and without it the discount
        // agent is rejected by the PendlePriceCapAdapter and the eMode agent by the PoolConfigurator.
        require(
            IACLManager(EthereumCoreExternalAddresses.AAVE_ACL_MANAGER).isRiskAdmin(expectedAgent),
            string.concat("WireEthereumCoreRoutes: ", label, " agent is not a RISK_ADMIN")
        );
    }

    function _requireRangeConfigured(uint256 agentId, string memory updateType) internal view {
        IRangeValidationModule module = IRangeValidationModule(EthereumCoreExternalAddresses.RANGE_VALIDATION_MODULE);
        IRangeValidationModule.RangeConfig memory config =
            module.getDefaultRangeConfig(EthereumCoreExternalAddresses.AGENT_HUB, agentId, updateType);

        require(
            config.maxIncrease != 0 || config.maxDecrease != 0,
            string.concat("WireEthereumCoreRoutes: no range config for ", updateType)
        );
    }

    function _workflow(bytes32 id, string memory name) internal pure returns (Workflow memory) {
        require(id != bytes32(0), string.concat("WireEthereumCoreRoutes: workflow id unset for ", name));
        return Workflow({ id: id, name: creWorkflowName(name) });
    }

    function _singleton(uint256 value) internal pure returns (uint256[] memory out) {
        out = new uint256[](1);
        out[0] = value;
    }

    /// @notice Derives the `bytes10` the Router compares against from a full CRE workflow name.
    /// @dev    Mirrors `HashTruncateName` in `chainlink-common/pkg/workflows`: sha256 the name, hex
    ///         encode the digest, keep the first ten hex characters, store those ten ASCII bytes.
    ///         There is no branch on name length. A ten character name is hashed exactly like a
    ///         thirty character one, so the raw name is NEVER the answer and
    ///         `cast format-bytes32-string "<name>"` is always wrong here.
    ///
    ///         Derived here rather than passed in because `addRoute` accepts any wrong name (only
    ///         `bytes10(0)` is rejected), there is no setter to correct it, and the mistake surfaces
    ///         only when the first live report is rejected. Repairing it costs a `removeRoute` plus
    ///         a re-registration, both owner calls on the safe.
    function creWorkflowName(string memory workflowName) public pure returns (bytes10) {
        require(bytes(workflowName).length != 0, "WireEthereumCoreRoutes: empty workflow name");

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
