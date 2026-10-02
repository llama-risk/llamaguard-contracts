// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { PlasmaCoreForkTest } from "./PlasmaCoreForkTest.sol";
import { LlamaguardRiskOracleRouter } from "../../../../src/LlamaguardRiskOracleRouter.sol";
import { PTParameterRegistry } from "../../../../src/PTParameterRegistry.sol";
import { IAgentHub } from "chaos-agents/interfaces/IAgentHub.sol";
import { IAgentConfigurator } from "chaos-agents/interfaces/IAgentConfigurator.sol";
import { IRangeValidationModule } from "chaos-agents/interfaces/IRangeValidationModule.sol";
import { IACLManager } from "aave-address-book/AaveV3.sol";
import { ActivatePlasmaCore } from "../../../../script/risk-oracles/plasma/production/1_ActivatePlasmaCore.s.sol";
import {
    ActivatePTsUSDe22OCT2026
} from "../../../../script/risk-oracles/plasma/production/2_ActivatePTsUSDe22OCT2026.s.sol";
import { WireAgentRoutes } from "../../../../script/risk-oracles/plasma/production/3b_WireAgentRoutes.s.sol";
import {
    WirePlasmaCoreRoutesBase
} from "../../../../script/risk-oracles/plasma/production/WirePlasmaCoreRoutesBase.sol";
import { PlasmaCoreConfig } from "../../../../script/risk-oracles/plasma/production/PlasmaCoreConfig.sol";
import {
    PlasmaCoreExternalAddresses
} from "../../../../script/risk-oracles/plasma/production/PlasmaCoreExternalAddresses.sol";
import { PTsUSDe22OCT2026 } from "../../../../script/risk-oracles/plasma/production/assets/PTsUSDe22OCT2026.sol";
import { SafeTx } from "../../../../script/risk-oracles/ethereum/production/SafeTx.sol";

/// @notice Stands in for an agent contract on the live hub.
/// @dev    `AgentConfigurator.registerAgent` stores configuration and never calls into the agent, so
///         registration needs nothing of it. That is what lets this suite exercise phase 3's
///         verification against the real AgentHub without depending on the Aave agent sources: what
///         belongs here is our route wiring and our reading of what governance left behind. The
///         injection itself is asserted where the payload lives.
contract PlasmaStubAgent { }

/// @notice Fork exercise of phase 3, the route wiring, against live Plasma.
/// @dev    Skips unless `PLASMA_RPC_URL` is set and the `fork` profile is active:
///
///           FOUNDRY_PROFILE=fork forge test --match-path "tests/risk-oracles/script/plasma-production/*"
contract PlasmaCoreRoutesForkTest is PlasmaCoreForkTest {
    ActivatePlasmaCore internal step1;
    ActivatePTsUSDe22OCT2026 internal step2;
    WireAgentRoutes internal step3;

    struct Stack {
        address riskOracle;
        address registry;
        address router;
        address emaOracle;
        address discountAgent;
        address emodeAgent;
        uint256 discountAgentId;
        uint256 emodeAgentId;
    }

    /// @dev Arbitrary but distinct. Workflow ids do not exist until `cre workflow deploy`, and the
    ///      shapes are what the Router cares about, not the values.
    bytes32 internal constant EMA_ID = bytes32(uint256(0xE4A));
    bytes32 internal constant DISCOUNT_ID = bytes32(uint256(0xD15));
    bytes32 internal constant RISK_PARAMS_ID = bytes32(uint256(0x8B5));

    function setUp() public {
        _setUpFork();
        if (!forked) return;

        step1 = new ActivatePlasmaCore();
        step2 = new ActivatePTsUSDe22OCT2026();
        step3 = new WireAgentRoutes();
    }

    function test_theRouteBatchRegistersThreeLiveRoutes() public {
        _skipUnlessForked();

        Stack memory stack = _throughPhase3();
        LlamaguardRiskOracleRouter router = LlamaguardRiskOracleRouter(stack.router);

        _assertRouteLive(router, EMA_ID);
        _assertRouteLive(router, DISCOUNT_ID);
        _assertRouteLive(router, RISK_PARAMS_ID);

        // The discount route is the only one carrying a real cap, and the two tuple routes express
        // the guard as off rather than as a number that would silently never apply.
        (,,,,, uint64 discountStep,) = router.routes(DISCOUNT_ID);
        assertEq(discountStep, PTsUSDe22OCT2026.DISCOUNT_ROUTER_MAX_STEP, "discount step cap");
        (,,,,, uint64 emaStep,) = router.routes(EMA_ID);
        assertEq(emaStep, PlasmaCoreConfig.ROUTER_MAX_STEP_OFF, "EMA step guard should be off");
    }

    /// @dev The EMA route is registered for the bare payload and the two agent routes for the
    ///      envelope, matching which workflows wrap. Getting this backwards bricks a route.
    function test_onlyTheAgentRoutesCarryTheReplayGuard() public {
        _skipUnlessForked();

        Stack memory stack = _throughPhase3();
        LlamaguardRiskOracleRouter router = LlamaguardRiskOracleRouter(stack.router);

        (,,,,,, uint64 emaAge) = router.routes(EMA_ID);
        (,,,,,, uint64 discountAge) = router.routes(DISCOUNT_ID);
        (,,,,,, uint64 riskParamsAge) = router.routes(RISK_PARAMS_ID);

        assertEq(emaAge, 0, "EMA route should expect the bare payload");
        assertEq(discountAge, PlasmaCoreConfig.MAX_REPORT_AGE_SECONDS, "discount route replay guard");
        assertEq(riskParamsAge, PlasmaCoreConfig.MAX_REPORT_AGE_SECONDS, "risk-params route replay guard");
    }

    // ============================================================================================
    // What phase 3 refuses to wire
    // ============================================================================================

    /// @dev The grant is the item most easily dropped from a payload, and without it every injection
    ///      reverts inside the Router's `try`, which is to say silently. This is the check that turns
    ///      that into a failure before any route exists.
    function test_phase3RefusesWhenTheAipForgotRiskAdmin() public {
        _skipUnlessForked();

        Stack memory stack = _throughPhase2();
        _simulateAip(stack, false, true);

        vm.expectRevert(bytes("WirePlasmaCoreRoutes: discount agent is not a RISK_ADMIN"));
        step3.requireTheAipLanded(_context(stack));
    }

    /// @dev A fresh agent id inherits no default range config and the module reads a missing one as a
    ///      zero bound, so an unset range is a dead agent rather than an unbounded one.
    function test_phase3RefusesWhenTheAipForgotTheRangeConfigs() public {
        _skipUnlessForked();

        Stack memory stack = _throughPhase2();
        _simulateAip(stack, true, false);

        vm.expectRevert(bytes("WirePlasmaCoreRoutes: no range config for PendleDiscountRateUpdate"));
        step3.requireTheAipLanded(_context(stack));
    }

    /// @dev Agent id 0 is a legitimate hub id, so the ids cannot be sanity checked against zero. The
    ///      identity check is against the recorded address, which is what catches a transposition.
    function test_phase3RefusesWhenTheAgentIdsAreSwapped() public {
        _skipUnlessForked();

        Stack memory stack = _throughPhase2();
        _simulateAip(stack, true, true);

        WirePlasmaCoreRoutesBase.Context memory ctx = _context(stack);
        (ctx.discountAgentId, ctx.emodeAgentId) = (ctx.emodeAgentId, ctx.discountAgentId);

        vm.expectRevert(bytes("WirePlasmaCoreRoutes: id is not the discount agent"));
        step3.requireTheAipLanded(ctx);
    }

    // ============================================================================================
    // Helpers
    // ============================================================================================

    /// @dev Phase 1, the safe accepting the Router, phase 2, and the registry write the safe makes.
    function _throughPhase2() internal returns (Stack memory stack) {
        PlasmaCoreConfig.Acl memory acl = PlasmaCoreConfig.acl();

        ActivatePlasmaCore.Deployment memory core = step1.deploy(address(step1), acl);
        stack.riskOracle = core.riskOracle;
        stack.registry = core.ptParameterRegistry;
        stack.router = core.router;

        // Phase 1 ends with the safe accepting the Router.
        vm.prank(acl.routerOwner);
        LlamaguardRiskOracleRouter(stack.router).acceptOwnership();

        stack.emaOracle = step2.deploy(address(step2), stack.router, acl).emaOracle;

        vm.prank(acl.registryUpdater);
        PTParameterRegistry(stack.registry)
            .setPtMarketParams(PTsUSDe22OCT2026.PT_ASSET, PTsUSDe22OCT2026.ptMarketParams());
    }

    function _throughPhase3() internal returns (Stack memory stack) {
        stack = _throughPhase2();
        _simulateAip(stack, true, true);
        _executeRouteBatch(stack);
    }

    /// @notice The AIP, expressed as pranked Executor calls: register both agents, grant
    ///         `RISK_ADMIN`, and set the four range configs.
    /// @dev    The flags exist so the negative tests can leave out exactly one of the two things a
    ///         payload most easily forgets, and nothing else.
    function _simulateAip(Stack memory stack, bool grantRiskAdmin, bool setRanges) internal {
        IAgentHub hub = IAgentHub(PlasmaCoreExternalAddresses.AGENT_HUB);
        address executor = PlasmaCoreExternalAddresses.AAVE_EXECUTOR;

        stack.discountAgent = address(new PlasmaStubAgent());
        stack.emodeAgent = address(new PlasmaStubAgent());

        address[] memory ptMarkets = new address[](1);
        ptMarkets[0] = PTsUSDe22OCT2026.PT_ASSET;

        vm.startPrank(executor);

        stack.discountAgentId =
            _register(hub, stack, stack.discountAgent, PlasmaCoreConfig.TYPE_DISCOUNT, bytes(""), ptMarkets);
        stack.emodeAgentId = _register(
            hub,
            stack,
            stack.emodeAgent,
            PlasmaCoreConfig.TYPE_EMODE,
            abi.encode(address(0xE9)),
            PTsUSDe22OCT2026.emodeMarkets()
        );

        if (grantRiskAdmin) {
            IACLManager(PlasmaCoreExternalAddresses.AAVE_ACL_MANAGER).addRiskAdmin(stack.discountAgent);
            IACLManager(PlasmaCoreExternalAddresses.AAVE_ACL_MANAGER).addRiskAdmin(stack.emodeAgent);
        }

        if (setRanges) {
            _setDefaultRange(stack.discountAgentId, PlasmaCoreConfig.TYPE_DISCOUNT, PTsUSDe22OCT2026.DISCOUNT_RANGE_ABS);
            _setDefaultRange(stack.emodeAgentId, "EModeLTV", PTsUSDe22OCT2026.EMODE_RANGE_ABS_BPS);
            _setDefaultRange(stack.emodeAgentId, "EModeLiquidationThreshold", PTsUSDe22OCT2026.EMODE_RANGE_ABS_BPS);
            _setDefaultRange(stack.emodeAgentId, "EModeLiquidationBonus", PTsUSDe22OCT2026.EMODE_RANGE_ABS_BPS);
        }

        vm.stopPrank();
    }

    function _register(
        IAgentHub hub,
        Stack memory stack,
        address agent,
        string memory updateType,
        bytes memory agentContext,
        address[] memory allowedMarkets
    )
        internal
        returns (uint256)
    {
        return hub.registerAgent(
            IAgentConfigurator.AgentRegistrationInput({
                admin: PlasmaCoreExternalAddresses.AAVE_PROTOCOL_GUARDIAN,
                riskOracle: stack.riskOracle,
                isAgentEnabled: true,
                isAgentPermissioned: false,
                isMarketsFromAgentEnabled: false,
                agentAddress: agent,
                expirationPeriod: PTsUSDe22OCT2026.DISCOUNT_AGENT_EXPIRATION_PERIOD,
                minimumDelay: PTsUSDe22OCT2026.DISCOUNT_AGENT_MINIMUM_DELAY,
                updateType: updateType,
                agentContext: agentContext,
                allowedMarkets: allowedMarkets,
                restrictedMarkets: new address[](0),
                permissionedSenders: new address[](0)
            })
        );
    }

    /// @dev Absolute bounds, not relative: a relative cap is measured against a previous injection
    ///      that a fresh id does not have, which would leave the first one unbounded.
    function _setDefaultRange(uint256 agentId, string memory updateType, uint120 bound) internal {
        IRangeValidationModule.RangeConfig memory cfg = IRangeValidationModule.RangeConfig({
            maxIncrease: bound, maxDecrease: bound, isIncreaseRelative: false, isDecreaseRelative: false
        });
        IRangeValidationModule module = IRangeValidationModule(PlasmaCoreExternalAddresses.RANGE_VALIDATION_MODULE);
        module.setDefaultRangeConfig(PlasmaCoreExternalAddresses.AGENT_HUB, agentId, updateType, cfg);
    }

    function _context(Stack memory stack) internal pure returns (WirePlasmaCoreRoutesBase.Context memory) {
        return WirePlasmaCoreRoutesBase.Context({
            router: stack.router,
            riskOracle: stack.riskOracle,
            emaOracle: stack.emaOracle,
            agentHub: PlasmaCoreExternalAddresses.AGENT_HUB,
            discountAgentId: stack.discountAgentId,
            emodeAgentId: stack.emodeAgentId,
            discountAgent: stack.discountAgent,
            emodeAgent: stack.emodeAgent,
            emaWorkflowId: EMA_ID,
            discountWorkflowId: DISCOUNT_ID,
            riskParamsWorkflowId: RISK_PARAMS_ID
        });
    }

    /// @dev Executes phase 3's batch exactly as the safe will: the same encoded calls, in the same
    ///      order, from the same signer. Nothing here re-derives what the script computed.
    function _executeRouteBatch(Stack memory stack) internal {
        WirePlasmaCoreRoutesBase.Context memory ctx = _context(stack);
        SafeTx.Call[] memory ema = step3.emaCalls(ctx);
        SafeTx.Call[] memory agents = step3.agentCalls(ctx);
        assertEq(ema.length, 2, "expected one addRoute plus one setRouteThrottle for the EMA route");
        assertEq(agents.length, 4, "expected two addRoute plus two setRouteThrottle for the agent routes");

        _execute(ema);
        _execute(agents);
    }

    /// @dev Runs one phase's calls from the Router owner, in order, surfacing the original revert.
    function _execute(SafeTx.Call[] memory calls) internal {
        for (uint256 i = 0; i < calls.length; i++) {
            vm.prank(PlasmaCoreConfig.ROUTER_OWNER);
            (bool ok, bytes memory reason) = calls[i].to.call(calls[i].data);
            if (!ok) {
                assembly {
                    revert(add(reason, 0x20), mload(reason))
                }
            }
        }
    }

    /// @dev A route is only live once its throttle is set: `addRoute` leaves `maxStepBps` at 0,
    ///      which for a scalar payload means frozen rather than unguarded.
    function _assertRouteLive(LlamaguardRiskOracleRouter router_, bytes32 workflowId) internal view {
        assertTrue(router_.getWorkflowConfig(workflowId).isActive, "route not registered");
        (,,, bool enabled,, uint64 maxStepBps,) = router_.routes(workflowId);
        assertTrue(enabled, "route registered but disabled");
        assertTrue(maxStepBps != 0, "route left frozen: setRouteThrottle did not run");
    }
}
