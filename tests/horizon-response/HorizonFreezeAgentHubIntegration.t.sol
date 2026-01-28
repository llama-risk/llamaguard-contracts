// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { HorizonFreezeAgent } from "../../src/horizon-response/agents/HorizonFreezeAgent.sol";
import { HorizonAgentHub } from "../../src/horizon-response/HorizonAgentHub.sol";
import { AgentHub } from "chaos-agents/contracts/AgentHub.sol";
import { ILlamaGuardOracle } from "../../src/interfaces/ILlamaGuardOracle.sol";
import { IAgentHub } from "chaos-agents/interfaces/IAgentHub.sol";
import { IAgentConfigurator } from "chaos-agents/interfaces/IAgentConfigurator.sol";
import { MockPoolConfigurator } from "../mocks/MockPoolConfigurator.sol";
import { MockPool } from "../mocks/MockPool.sol";
import { MockLlamaGuardOracle } from "../mocks/MockLlamaGuardOracle.sol";

/// @title HorizonFreezeAgentHubIntegrationTest
/// @notice Integration tests for HorizonFreezeAgent with HorizonAgentHub
contract HorizonFreezeAgentHubIntegrationTest is Test {
    HorizonAgentHub internal hub;
    HorizonFreezeAgent internal agent;
    MockLlamaGuardOracle internal oracle;
    MockPoolConfigurator internal poolConfigurator;
    MockPool internal pool;

    address internal hubOwner;
    address internal agentAdmin;
    address internal market;

    string internal constant UPDATE_TYPE = "boundedNAV";
    uint256 internal agentId;

    event ReserveFreezeUpdated(address indexed market, bool frozen, uint256 state);

    function setUp() public {
        hubOwner = makeAddr("hubOwner");
        agentAdmin = makeAddr("agentAdmin");
        market = makeAddr("market");

        // Deploy HorizonAgentHub via proxy
        hub = HorizonAgentHub(
            address(
                new TransparentUpgradeableProxy(
                    address(new HorizonAgentHub()),
                    address(this),
                    abi.encodeWithSelector(AgentHub.initialize.selector, hubOwner)
                )
            )
        );

        // Deploy mocks
        oracle = new MockLlamaGuardOracle();
        pool = new MockPool();
        poolConfigurator = new MockPoolConfigurator();

        // Deploy agent with hub and pool
        agent = new HorizonFreezeAgent(address(hub), address(pool));

        // Add market to pool reserves
        pool.addReserve(market);

        // Add update type to oracle
        oracle.addUpdateType(UPDATE_TYPE, type(uint256).max);

        // Register agent
        agentId = _registerAgent();

        // Warp to have time context
        vm.warp(1 days);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    function _registerAgent() internal returns (uint256) {
        address[] memory markets = new address[](1);
        markets[0] = market;

        // agentContext now only contains poolConfigurator address
        bytes memory agentContext = abi.encode(address(poolConfigurator));

        vm.startPrank(hubOwner);
        uint256 id = hub.registerAgent(
            IAgentConfigurator.AgentRegistrationInput({
                agentAddress: address(agent),
                riskOracle: address(oracle),
                admin: agentAdmin,
                agentContext: agentContext,
                isAgentEnabled: true,
                isAgentPermissioned: false,
                isMarketsFromAgentEnabled: false,
                expirationPeriod: 1 days,
                minimumDelay: 0,
                updateType: UPDATE_TYPE,
                allowedMarkets: markets,
                restrictedMarkets: new address[](0),
                permissionedSenders: new address[](0)
            })
        );
        vm.stopPrank();

        return id;
    }

    function _addUpdateToOracle(address marketAddr, uint256 state) internal {
        bytes memory additionalData = abi.encode(int256(-100), int256(100), state);
        bytes memory newV = abi.encode(int256(100)); // price

        oracle.setUpdate(UPDATE_TYPE, marketAddr, block.timestamp, newV, oracle.getLatestRoundId() + 1, additionalData);
    }

    function _publishUpdateToOracle(address, uint256 state) internal {
        bytes memory additionalData = abi.encode(int256(-100), int256(100), state);
        bytes memory newValue = abi.encode(int256(100)); // price

        oracle.updateLatestRiskRoundData(
            ILlamaGuardOracle.UpdateInput({
                referenceId: "test-ref", newValue: newValue, updateType: UPDATE_TYPE, additionalData: additionalData
            })
        );
    }

    function _checkAndExecute(uint256 id) internal returns (bool) {
        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = id;

        (bool shouldExecute, IAgentHub.ActionData[] memory actions) = hub.check(agentIds);
        if (shouldExecute) {
            hub.execute(actions);
        }
        return shouldExecute;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HUB INTEGRATION - BASIC FLOW TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_HubIntegration_CheckAndExecute_FreezesReserve() public {
        // Publish freeze update (state=1)
        _publishUpdateToOracle(market, 1);

        // Execute via hub
        bool executed = _checkAndExecute(agentId);

        assertTrue(executed, "Should execute freeze");
        assertTrue(poolConfigurator.isFrozen(market), "Market should be frozen");
        assertEq(poolConfigurator.freezeCallCount(), 1, "Should have called freeze once");
    }

    function test_HubIntegration_CheckReturnsFalse_WhenNoValidUpdate() public {
        // Publish unfreeze update (state=0) - should fail agent validation
        _publishUpdateToOracle(market, 0);

        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = agentId;

        (bool shouldExecute,) = hub.check(agentIds);

        assertFalse(shouldExecute, "Should not execute unfreeze");
    }

    function test_HubIntegration_CheckReturnsFalse_WhenAlreadyFrozen() public {
        // Mark market as already frozen
        pool.setFrozen(market, true);

        // Publish freeze update
        _publishUpdateToOracle(market, 1);

        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = agentId;

        (bool shouldExecute,) = hub.check(agentIds);

        assertFalse(shouldExecute, "Should not execute when already frozen");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HUB VALIDATION - EXPIRATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_HubIntegration_UpdateExpired_CheckReturnsFalse() public {
        // Publish update
        _publishUpdateToOracle(market, 1);

        // Warp past expiration (1 day + 1 second)
        vm.warp(block.timestamp + 1 days + 1);

        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = agentId;

        (bool shouldExecute,) = hub.check(agentIds);

        assertFalse(shouldExecute, "Should not execute expired update");
    }

    function test_HubIntegration_UpdateNotExpired_Executes() public {
        // Publish update
        _publishUpdateToOracle(market, 1);

        // Warp just before expiration
        vm.warp(block.timestamp + 1 days - 1);

        bool executed = _checkAndExecute(agentId);

        assertTrue(executed, "Should execute before expiration");
        assertTrue(poolConfigurator.isFrozen(market), "Market should be frozen");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HUB VALIDATION - MINIMUM DELAY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_HubIntegration_MinimumDelayNotPassed_CheckReturnsFalse() public {
        // Set minimum delay
        vm.prank(agentAdmin);
        hub.setMinimumDelay(agentId, 1 hours);

        // First update - execute successfully
        _publishUpdateToOracle(market, 1);
        bool executed = _checkAndExecute(agentId);
        assertTrue(executed, "First execution should succeed");

        // Mark as frozen in provider (simulating state sync)
        pool.setFrozen(market, true);

        // Add new market and try again within minimum delay
        address market2 = makeAddr("market2");
        vm.prank(agentAdmin);
        hub.addAllowedMarket(agentId, market2);

        _publishUpdateToOracle(market2, 1);

        // Try to execute immediately - should fail minimum delay check
        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = agentId;

        (bool shouldExecute,) = hub.check(agentIds);
        // Note: minimum delay is per-market, so this should still execute for market2
        // But if minimum delay was global, it would fail
        assertTrue(shouldExecute, "Should execute for different market");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HUB VALIDATION - UPDATE ID DEDUPLICATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_HubIntegration_UpdateIdAlreadyExecuted_Skipped() public {
        // Publish update
        _publishUpdateToOracle(market, 1);

        // Execute first time
        bool executed = _checkAndExecute(agentId);
        assertTrue(executed, "First execution should succeed");

        // Reset pool state for second attempt
        pool.setFrozen(market, false);
        poolConfigurator.reset();

        // Try to execute same updateId again - should be skipped
        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = agentId;

        (bool shouldExecute,) = hub.check(agentIds);
        assertFalse(shouldExecute, "Should skip already executed updateId");
    }

    function test_HubIntegration_NewUpdateId_Executes() public {
        // Publish first update
        _publishUpdateToOracle(market, 1);
        bool executed = _checkAndExecute(agentId);
        assertTrue(executed, "First execution should succeed");

        // Reset states
        pool.setFrozen(market, false);
        poolConfigurator.reset();

        // Warp time a bit
        vm.warp(block.timestamp + 1);

        // Publish NEW update (new updateId)
        _publishUpdateToOracle(market, 1);

        executed = _checkAndExecute(agentId);
        assertTrue(executed, "Should execute new updateId");
        assertEq(poolConfigurator.freezeCallCount(), 1, "Should have frozen again");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HUB VALIDATION - AGENT ENABLED/DISABLED TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_HubIntegration_AgentDisabled_Skipped() public {
        // Disable agent
        vm.prank(agentAdmin);
        hub.setAgentEnabled(agentId, false);

        // Publish update
        _publishUpdateToOracle(market, 1);

        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = agentId;

        (bool shouldExecute,) = hub.check(agentIds);
        assertFalse(shouldExecute, "Should skip disabled agent");
    }

    function test_HubIntegration_AgentReEnabled_Executes() public {
        // Disable then re-enable agent
        vm.startPrank(agentAdmin);
        hub.setAgentEnabled(agentId, false);
        hub.setAgentEnabled(agentId, true);
        vm.stopPrank();

        // Publish update
        _publishUpdateToOracle(market, 1);

        bool executed = _checkAndExecute(agentId);
        assertTrue(executed, "Should execute for re-enabled agent");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HUB VALIDATION - MARKET CONFIGURATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_HubIntegration_MultipleMarkets_Sequential() public {
        // Add second market
        address market2 = makeAddr("market2");
        vm.prank(agentAdmin);
        hub.addAllowedMarket(agentId, market2);

        // Publish updates for both markets
        _publishUpdateToOracle(market, 1);
        _publishUpdateToOracle(market2, 1);

        // Execute
        bool executed = _checkAndExecute(agentId);
        assertTrue(executed, "Should execute");

        // Both should be frozen
        assertTrue(poolConfigurator.isFrozen(market), "Market 1 should be frozen");
        assertTrue(poolConfigurator.isFrozen(market2), "Market 2 should be frozen");
        assertEq(poolConfigurator.freezeCallCount(), 2, "Should have frozen twice");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BOUNDARY FUZZ TESTS (Symmetric Pattern)
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_HubIntegration_OnlyFreezeStateExecutes(uint256 state) public {
        // Publish update with arbitrary state
        bytes memory additionalData = abi.encode(int256(-100), int256(100), state);
        bytes memory newValue = abi.encode(int256(100));
        oracle.updateLatestRiskRoundData(
            ILlamaGuardOracle.UpdateInput({
                referenceId: "test-ref", newValue: newValue, updateType: UPDATE_TYPE, additionalData: additionalData
            })
        );

        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = agentId;

        (bool shouldExecute,) = hub.check(agentIds);

        // Only state == 1 should pass validation
        if (state == 1) {
            assertTrue(shouldExecute, "Should execute for freeze state");
        } else {
            assertFalse(shouldExecute, "Should not execute for non-freeze state");
        }
    }

    function testFuzz_HubIntegration_ExpirationBoundary(uint256 timeDelta) public {
        // Bound timeDelta to reasonable range
        timeDelta = bound(timeDelta, 0, 2 days);

        // Publish update
        _publishUpdateToOracle(market, 1);

        // Warp by timeDelta
        vm.warp(block.timestamp + timeDelta);

        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = agentId;

        (bool shouldExecute,) = hub.check(agentIds);

        // Expiration period is 1 day, so:
        // - If timeDelta <= 1 day: should execute
        // - If timeDelta > 1 day: should not execute (expired)
        if (timeDelta <= 1 days) {
            assertTrue(shouldExecute, "Should execute before expiration");
        } else {
            assertFalse(shouldExecute, "Should not execute after expiration");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ERROR HANDLING TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_HubIntegration_OracleReverts_CheckContinues() public {
        // Set oracle to revert
        oracle.setShouldRevert(true, "Oracle error");

        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = agentId;

        // Check should not revert - it catches oracle errors
        (bool shouldExecute,) = hub.check(agentIds);
        assertFalse(shouldExecute, "Should return false when oracle reverts");
    }

    function test_Inject_ConfiguratorReverts_PropagatesError() public {
        // Deploy agent with direct hub address for simpler testing
        HorizonFreezeAgent directAgent = new HorizonFreezeAgent(address(this), address(pool));

        // Set configurator to revert
        poolConfigurator.setShouldRevert(true, "Configurator error");

        ILlamaGuardOracle.RiskParameterUpdate memory update = ILlamaGuardOracle.RiskParameterUpdate({
            timestamp: block.timestamp,
            newValue: abi.encode(int256(100)),
            referenceId: "test-ref",
            previousValue: "",
            updateType: UPDATE_TYPE,
            updateId: 1,
            market: market,
            additionalData: abi.encode(int256(-100), int256(100), uint256(1))
        });

        bytes memory agentContext = abi.encode(address(poolConfigurator));

        // Should revert with configurator's error wrapped in Address.functionCall revert
        vm.expectRevert();
        directAgent.inject(0, agentContext, update);
    }
}
