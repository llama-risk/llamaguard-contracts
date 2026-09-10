// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { EthereumCoreAssetForkBase } from "./EthereumCoreAssetForkBase.sol";
import { LlamaguardRiskOracleRouter } from "../../../../src/LlamaguardRiskOracleRouter.sol";
import { RiskOracle } from "aave-v3-risk-stewards/contracts/dependencies/RiskOracle.sol";
import { IAgentHub } from "chaos-agents/interfaces/IAgentHub.sol";
import { IAgentConfigurator } from "chaos-agents/interfaces/IAgentConfigurator.sol";
import { IRangeValidationModule } from "chaos-agents/interfaces/IRangeValidationModule.sol";
import { IACLManager } from "aave-address-book/AaveV3.sol";
import { WireAgentRoutes } from "../../../../script/risk-oracles/ethereum/production/3b_WireAgentRoutes.s.sol";
import {
    WireEthereumCoreRoutesBase
} from "../../../../script/risk-oracles/ethereum/production/WireEthereumCoreRoutesBase.sol";
import { EthereumCoreConfig } from "../../../../script/risk-oracles/ethereum/production/EthereumCoreConfig.sol";
import {
    EthereumCoreExternalAddresses
} from "../../../../script/risk-oracles/ethereum/production/EthereumCoreExternalAddresses.sol";
import { PTsrUSDe22OCT2026 } from "../../../../script/risk-oracles/ethereum/production/assets/PTsrUSDe22OCT2026.sol";
import { SafeTx } from "../../../../script/risk-oracles/ethereum/production/SafeTx.sol";

/// @notice Stands in for an agent contract on the live hub.
/// @dev    `AgentConfigurator.registerAgent` stores configuration and never calls into the agent, so
///         registration needs nothing of it. That is what lets this suite exercise phase 3's
///         verification against the real AgentHub without depending on the Aave agent sources, which
///         is the right split now that the payload deploys them: what belongs here is our route
///         wiring and our reading of what governance left behind. The injection itself is asserted
///         where the payload lives.

/// @notice Stands in for an agent contract on the live hub.
/// @dev    `AgentConfigurator.registerAgent` stores configuration and never calls into the agent, so
///         registration needs nothing of it. That is what lets this suite exercise phase 3's
///         verification against the real AgentHub without depending on the Aave agent sources, which
///         is the right split now that the payload deploys them: what belongs here is our route
///         wiring and our reading of what governance left behind. The injection itself is asserted
///         where the payload lives.
contract StubAgent { }

/// @notice Fork exercise of phase 3, the route wiring, against live Ethereum mainnet.
/// @dev    Skips unless `MAINNET_RPC_URL` is set and the `fork` profile is active:
///
///           FOUNDRY_PROFILE=fork forge test --match-path "tests/script/ethereum-production/*"
contract EthereumCoreRoutesForkTest is EthereumCoreAssetForkBase {
    WireAgentRoutes internal step3;

    /// @dev Arbitrary but distinct. Workflow ids do not exist until `cre workflow deploy`, and the
    ///      shapes are what the Router cares about, not the values.
    bytes32 internal constant EMA_ID = bytes32(uint256(0xE4A));
    bytes32 internal constant DISCOUNT_ID = bytes32(uint256(0xD15));
    bytes32 internal constant RISK_PARAMS_ID = bytes32(uint256(0x8B5));

    function setUp() public {
        _setUpThroughPhase2();
        if (!forked) return;

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
        assertEq(discountStep, PTsrUSDe22OCT2026.DISCOUNT_ROUTER_MAX_STEP, "discount step cap");
        (,,,,, uint64 emaStep,) = router.routes(EMA_ID);
        assertEq(emaStep, EthereumCoreConfig.ROUTER_MAX_STEP_OFF, "EMA step guard should be off");
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
        assertEq(discountAge, EthereumCoreConfig.MAX_REPORT_AGE_SECONDS, "discount route replay guard");
        assertEq(riskParamsAge, EthereumCoreConfig.MAX_REPORT_AGE_SECONDS, "risk-params route replay guard");
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

        vm.expectRevert(bytes("WireEthereumCoreRoutes: discount agent is not a RISK_ADMIN"));
        step3.requireTheAipLanded(_context(stack));
    }

    /// @dev A fresh agent id inherits no default range config and the module reads a missing one as a
    ///      zero bound, so an unset range is a dead agent rather than an unbounded one.
    function test_phase3RefusesWhenTheAipForgotTheRangeConfigs() public {
        _skipUnlessForked();

        Stack memory stack = _throughPhase2();
        _simulateAip(stack, true, false);

        vm.expectRevert(bytes("WireEthereumCoreRoutes: no range config for PendleDiscountRateUpdate"));
        step3.requireTheAipLanded(_context(stack));
    }

    /// @dev Agent id 0 is a legitimate hub id, so the ids cannot be sanity checked against zero. The
    ///      identity check is against the recorded address, which is what catches a transposition.
    function test_phase3RefusesWhenTheAgentIdsAreSwapped() public {
        _skipUnlessForked();

        Stack memory stack = _throughPhase2();
        _simulateAip(stack, true, true);

        WireEthereumCoreRoutesBase.Context memory ctx = _context(stack);
        (ctx.discountAgentId, ctx.emodeAgentId) = (ctx.emodeAgentId, ctx.discountAgentId);

        vm.expectRevert(bytes("WireEthereumCoreRoutes: id is not the discount agent"));
        step3.requireTheAipLanded(ctx);
    }

    // ============================================================================================

    // ============================================================================================
    // Helpers
    // ============================================================================================

    function _throughPhase3() internal returns (Stack memory stack) {
        stack = _throughPhase2();
        _simulateAip(stack, true, true);
        _executeRouteBatch(stack);
    }

    /// @notice The AIP, expressed as pranked Executor calls: deploy both agents, register them,
    ///         grant `RISK_ADMIN`, and set the four range configs.
    /// @dev    The flags exist so the negative tests can leave out exactly one of the two things a
    ///         payload most easily forgets, and nothing else.
    function _simulateAip(Stack memory stack, bool grantRiskAdmin, bool setRanges) internal {
        IAgentHub hub = IAgentHub(EthereumCoreExternalAddresses.AGENT_HUB);
        address executor = EthereumCoreExternalAddresses.AAVE_EXECUTOR;

        stack.discountAgent = address(new StubAgent());
        stack.emodeAgent = address(new StubAgent());

        address[] memory ptMarkets = new address[](1);
        ptMarkets[0] = PTsrUSDe22OCT2026.PT_ASSET;

        vm.startPrank(executor);

        stack.discountAgentId =
            _register(hub, stack, stack.discountAgent, EthereumCoreConfig.TYPE_DISCOUNT, bytes(""), ptMarkets);
        stack.emodeAgentId = _register(
            hub,
            stack,
            stack.emodeAgent,
            EthereumCoreConfig.TYPE_EMODE,
            abi.encode(address(0xE9)),
            PTsrUSDe22OCT2026.emodeMarkets()
        );

        if (grantRiskAdmin) {
            IACLManager(EthereumCoreExternalAddresses.AAVE_ACL_MANAGER).addRiskAdmin(stack.discountAgent);
            IACLManager(EthereumCoreExternalAddresses.AAVE_ACL_MANAGER).addRiskAdmin(stack.emodeAgent);
        }

        if (setRanges) {
            _setDefaultRange(
                stack.discountAgentId, EthereumCoreConfig.TYPE_DISCOUNT, PTsrUSDe22OCT2026.DISCOUNT_RANGE_ABS
            );
            _setDefaultRange(stack.emodeAgentId, "EModeLTV", PTsrUSDe22OCT2026.EMODE_RANGE_ABS_BPS);
            _setDefaultRange(stack.emodeAgentId, "EModeLiquidationThreshold", PTsrUSDe22OCT2026.EMODE_RANGE_ABS_BPS);
            _setDefaultRange(stack.emodeAgentId, "EModeLiquidationBonus", PTsrUSDe22OCT2026.EMODE_RANGE_ABS_BPS);
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
                admin: EthereumCoreExternalAddresses.AAVE_EXECUTOR,
                riskOracle: stack.riskOracle,
                isAgentEnabled: true,
                isAgentPermissioned: false,
                isMarketsFromAgentEnabled: false,
                agentAddress: agent,
                expirationPeriod: PTsrUSDe22OCT2026.DISCOUNT_AGENT_EXPIRATION_PERIOD,
                minimumDelay: PTsrUSDe22OCT2026.DISCOUNT_AGENT_MINIMUM_DELAY,
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
        IRangeValidationModule module = IRangeValidationModule(EthereumCoreExternalAddresses.RANGE_VALIDATION_MODULE);
        module.setDefaultRangeConfig(EthereumCoreExternalAddresses.AGENT_HUB, agentId, updateType, cfg);
    }

    function _context(Stack memory stack) internal pure returns (WireEthereumCoreRoutesBase.Context memory) {
        return WireEthereumCoreRoutesBase.Context({
            router: stack.router,
            riskOracle: stack.riskOracle,
            emaOracle: stack.emaOracle,
            agentHub: EthereumCoreExternalAddresses.AGENT_HUB,
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
        WireEthereumCoreRoutesBase.Context memory ctx = _context(stack);
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
            vm.prank(EthereumCoreConfig.ROUTER_OWNER);
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
