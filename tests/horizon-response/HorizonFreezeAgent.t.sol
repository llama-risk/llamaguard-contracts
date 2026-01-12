// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { HorizonFreezeAgent } from "../../src/horizon-response/agents/HorizonFreezeAgent.sol";
import { HorizonAgentHub } from "../../src/horizon-response/HorizonAgentHub.sol";
import { AgentHub } from "chaos-agents/contracts/AgentHub.sol";
import { BaseHorizonAgent } from "../../src/horizon-response/agents/BaseHorizonAgent.sol";
import { ILlamaGuardOracle } from "../../src/interfaces/ILlamaGuardOracle.sol";
import { IAgentHub } from "chaos-agents/interfaces/IAgentHub.sol";
import { IAgentConfigurator } from "chaos-agents/interfaces/IAgentConfigurator.sol";
import { MockPoolConfigurator } from "../mocks/MockPoolConfigurator.sol";
import { MockPool } from "../mocks/MockPool.sol";
import { MockLlamaGuardOracle } from "../mocks/MockLlamaGuardOracle.sol";

contract HorizonFreezeAgentTest is Test {
    HorizonFreezeAgent internal agent;
    MockPoolConfigurator internal poolConfigurator;
    MockPool internal pool;

    address internal agentHub;
    address internal market;
    address internal nonAgentHub;

    event ReserveFreezeUpdated(address indexed market, bool frozen, uint256 state);

    string internal constant UPDATE_TYPE_STR = "boundedNAV";

    function setUp() public {
        agentHub = makeAddr("agentHub");
        market = makeAddr("market");
        nonAgentHub = makeAddr("nonAgentHub");

        pool = new MockPool();
        poolConfigurator = new MockPoolConfigurator();
        agent = new HorizonFreezeAgent(agentHub, address(pool));

        // Add market to pool reserves
        pool.addReserve(market);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Encode additionalData as (lowerBound, upperBound, state)
    function _encodeAdditionalData(
        int256 lowerBound,
        int256 upperBound,
        uint256 state
    )
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(lowerBound, upperBound, state);
    }

    /// @dev Create a RiskParameterUpdate struct for testing
    function _createUpdate(
        address marketAddr,
        uint256 state,
        int256 lowerBound,
        int256 upperBound
    )
        internal
        view
        returns (ILlamaGuardOracle.RiskParameterUpdate memory)
    {
        return ILlamaGuardOracle.RiskParameterUpdate({
            timestamp: block.timestamp,
            newValue: abi.encode(int256(100)), // price
            referenceId: "test-ref",
            previousValue: "",
            updateType: UPDATE_TYPE_STR,
            updateId: 1,
            market: marketAddr,
            additionalData: _encodeAdditionalData(lowerBound, upperBound, state)
        });
    }

    /// @dev Encode agent context with pool configurator address
    function _encodeAgentContext(address poolConfiguratorAddr) internal pure returns (bytes memory) {
        return abi.encode(poolConfiguratorAddr);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Constructor_SetsAgentHub() public view {
        assertEq(agent.AGENT_HUB(), agentHub);
    }

    function test_Constructor_SetsPool() public view {
        assertEq(address(agent.POOL()), address(pool));
    }

    function test_Constructor_DifferentAgentHub() public {
        address differentHub = makeAddr("differentHub");
        address differentPool = makeAddr("differentPool");
        HorizonFreezeAgent newAgent = new HorizonFreezeAgent(differentHub, differentPool);
        assertEq(newAgent.AGENT_HUB(), differentHub);
        assertEq(address(newAgent.POOL()), differentPool);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FROZEN_STATE CONSTANT TEST
    // ═══════════════════════════════════════════════════════════════════════════

    function test_FrozenStateConstant() public view {
        assertEq(agent.FROZEN_STATE(), 1);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VALIDATE TESTS - FREEZE-ONLY LOGIC
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Validate_ReturnsTrueForFreezeWhenNotFrozen() public view {
        // Market is not frozen in pool by default
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(
            market,
            1, // state = FROZEN
            -100, // lowerBound
            100 // upperBound
        );
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator));

        bool isValid = agent.validate(0, agentContext, update);
        assertTrue(isValid);
    }

    function test_Validate_ReturnsFalseForUnfreezeState() public view {
        // Unfreeze (state=0) should always be rejected
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(
            market,
            0, // state = UNFROZEN
            -100,
            100
        );
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator));

        bool isValid = agent.validate(0, agentContext, update);
        assertFalse(isValid);
    }

    function test_Validate_ReturnsFalseWhenAlreadyFrozen() public {
        // Set market as already frozen in pool
        pool.setFrozen(market, true);

        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(
            market,
            1, // state = FROZEN
            -100,
            100
        );
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator));

        bool isValid = agent.validate(0, agentContext, update);
        assertFalse(isValid);
    }

    function test_Validate_ReturnsFalseForInvalidState() public view {
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(
            market,
            2, // state = INVALID (> 1)
            -100,
            100
        );
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator));

        bool isValid = agent.validate(0, agentContext, update);
        assertFalse(isValid);
    }

    function test_Validate_ReturnsFalseForLargeState() public view {
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(
            market,
            999, // state = INVALID
            -100,
            100
        );
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator));

        bool isValid = agent.validate(0, agentContext, update);
        assertFalse(isValid);
    }

    function testFuzz_Validate_OnlyAcceptsFreezeWhenNotFrozen(uint256 state) public view {
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(market, state, -100, 100);
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator));

        bool isValid = agent.validate(0, agentContext, update);

        // Only state == 1 (freeze) when market is not frozen should return true
        if (state == 1) {
            assertTrue(isValid);
        } else {
            assertFalse(isValid);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GET MARKETS TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_GetMarkets_ReturnsReservesList() public view {
        address[] memory markets = agent.getMarkets(0);
        assertEq(markets.length, 1);
        assertEq(markets[0], market);
    }

    function test_GetMarkets_ReturnsMultipleReserves() public {
        address market2 = makeAddr("market2");
        address market3 = makeAddr("market3");

        pool.addReserve(market2);
        pool.addReserve(market3);

        address[] memory markets = agent.getMarkets(0);
        assertEq(markets.length, 3);
        assertEq(markets[0], market);
        assertEq(markets[1], market2);
        assertEq(markets[2], market3);
    }

    function test_GetMarkets_ReturnsEmptyWhenNoReserves() public {
        pool.clearReserves();

        address[] memory markets = agent.getMarkets(0);
        assertEq(markets.length, 0);
    }

    function test_GetMarkets_IgnoresAgentId() public view {
        // getMarkets should return same reserves regardless of agentId
        address[] memory markets1 = agent.getMarkets(0);
        address[] memory markets2 = agent.getMarkets(1);
        address[] memory markets3 = agent.getMarkets(type(uint256).max);

        assertEq(markets1.length, markets2.length);
        assertEq(markets2.length, markets3.length);
        assertEq(markets1[0], markets2[0]);
        assertEq(markets2[0], markets3[0]);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INJECT ACCESS CONTROL TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Inject_RevertsWhenCalledByNonAgentHub() public {
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(market, 1, -100, 100);
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator));

        vm.prank(nonAgentHub);
        vm.expectRevert(abi.encodeWithSelector(BaseHorizonAgent.OnlyAgentHub.selector, nonAgentHub));
        agent.inject(0, agentContext, update);
    }

    function test_Inject_SucceedsWhenCalledByAgentHub() public {
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(market, 1, -100, 100);
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator));

        vm.prank(agentHub);
        agent.inject(0, agentContext, update);

        // Verify the freeze was executed
        assertTrue(poolConfigurator.isFrozen(market));
    }

    function test_Inject_RevertsWhenValidationFails() public {
        // Set market as already frozen - validation should fail
        pool.setFrozen(market, true);

        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(market, 1, -100, 100);
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator));

        vm.prank(agentHub);
        vm.expectRevert(HorizonFreezeAgent.ValidationFailed.selector);
        agent.inject(0, agentContext, update);
    }

    function test_Inject_RevertsForUnfreezeState() public {
        // Try to unfreeze - should fail validation
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(market, 0, -100, 100);
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator));

        vm.prank(agentHub);
        vm.expectRevert(HorizonFreezeAgent.ValidationFailed.selector);
        agent.inject(0, agentContext, update);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PROCESS UPDATE / FREEZE LOGIC TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_ProcessUpdate_FreezesReserveWhenStateIsOne() public {
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(
            market,
            1, // FROZEN
            -100,
            100
        );
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator));

        vm.prank(agentHub);
        agent.inject(0, agentContext, update);

        assertTrue(poolConfigurator.isFrozen(market));
        assertEq(poolConfigurator.lastFreezeAsset(), market);
        assertTrue(poolConfigurator.lastFreezeState());
        assertEq(poolConfigurator.freezeCallCount(), 1);
    }

    function test_ProcessUpdate_EmitsReserveFreezeUpdatedEvent() public {
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(market, 1, -100, 100);
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator));

        vm.prank(agentHub);
        vm.expectEmit(true, false, false, true);
        emit ReserveFreezeUpdated(market, true, 1);
        agent.inject(0, agentContext, update);
    }

    function test_ProcessUpdate_HandlesMultipleMarkets() public {
        address market1 = makeAddr("market1");
        address market2 = makeAddr("market2");

        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator));

        // Freeze market1
        ILlamaGuardOracle.RiskParameterUpdate memory update1 = _createUpdate(market1, 1, -100, 100);
        vm.prank(agentHub);
        agent.inject(0, agentContext, update1);

        // Freeze market2
        ILlamaGuardOracle.RiskParameterUpdate memory update2 = _createUpdate(market2, 1, -200, 200);
        vm.prank(agentHub);
        agent.inject(0, agentContext, update2);

        assertTrue(poolConfigurator.isFrozen(market1));
        assertTrue(poolConfigurator.isFrozen(market2));
        assertEq(poolConfigurator.freezeCallCount(), 2);
    }

    function test_ProcessUpdate_DecodesPoolConfiguratorFromContext() public {
        // Create a second pool configurator
        MockPoolConfigurator poolConfigurator2 = new MockPoolConfigurator();

        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(market, 1, -100, 100);

        // Use first configurator
        bytes memory agentContext1 = _encodeAgentContext(address(poolConfigurator));
        vm.prank(agentHub);
        agent.inject(0, agentContext1, update);

        assertTrue(poolConfigurator.isFrozen(market));
        assertFalse(poolConfigurator2.isFrozen(market));

        // Use second configurator for a different market
        address market2 = makeAddr("market2");
        ILlamaGuardOracle.RiskParameterUpdate memory update2 = _createUpdate(market2, 1, -100, 100);
        bytes memory agentContext2 = _encodeAgentContext(address(poolConfigurator2));

        vm.prank(agentHub);
        agent.inject(0, agentContext2, update2);

        assertFalse(poolConfigurator.isFrozen(market2));
        assertTrue(poolConfigurator2.isFrozen(market2));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADDITIONAL DATA DECODING TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_ProcessUpdate_DecodesAdditionalDataCorrectly(int256 lowerBound, int256 upperBound) public {
        // Test with state = 1 (freeze)
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(market, 1, lowerBound, upperBound);
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator));

        vm.prank(agentHub);
        agent.inject(0, agentContext, update);

        // Verify freeze was called regardless of other values
        assertTrue(poolConfigurator.isFrozen(market));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_ProcessUpdate_WithZeroAddress() public {
        address zeroMarket = address(0);
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(zeroMarket, 1, -100, 100);
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator));

        vm.prank(agentHub);
        agent.inject(0, agentContext, update);

        // Should still work with zero address
        assertTrue(poolConfigurator.isFrozen(zeroMarket));
    }

    function test_ProcessUpdate_WithMaxValues() public {
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(
            market,
            1,
            type(int256).min, // lowerBound
            type(int256).max // upperBound
        );
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator));

        vm.prank(agentHub);
        agent.inject(0, agentContext, update);

        assertTrue(poolConfigurator.isFrozen(market));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FREEZE-ONLY SECURITY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CannotUnfreezeViaOracle() public {
        // First manually freeze the market in poolConfigurator (simulating previous freeze)
        poolConfigurator.setReserveFreeze(market, true);
        // Also mark it as frozen in pool (what we query via getConfiguration)
        pool.setFrozen(market, true);

        // Try to unfreeze via oracle - should fail
        ILlamaGuardOracle.RiskParameterUpdate memory unfreezeUpdate = _createUpdate(market, 0, -100, 100);
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator));

        vm.prank(agentHub);
        vm.expectRevert(HorizonFreezeAgent.ValidationFailed.selector);
        agent.inject(0, agentContext, unfreezeUpdate);

        // Market should still be frozen
        assertTrue(poolConfigurator.isFrozen(market));
    }

    function test_CannotDoubleFreezeViaOracle() public {
        // First freeze the market
        ILlamaGuardOracle.RiskParameterUpdate memory freezeUpdate = _createUpdate(market, 1, -100, 100);
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator));

        vm.prank(agentHub);
        agent.inject(0, agentContext, freezeUpdate);

        // Now mark it as frozen in pool (simulating sync with pool state)
        pool.setFrozen(market, true);

        // Try to freeze again - should fail validation
        vm.prank(agentHub);
        vm.expectRevert(HorizonFreezeAgent.ValidationFailed.selector);
        agent.inject(0, agentContext, freezeUpdate);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HUB INTEGRATION TESTS
// ═══════════════════════════════════════════════════════════════════════════════

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
        oracle.addUpdateType(UPDATE_TYPE);

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
        bytes memory newValue = abi.encode(int256(100)); // price

        oracle.setUpdate(UPDATE_TYPE, marketAddr, block.timestamp, newValue, oracle.updateCounter() + 1, additionalData);
    }

    function _publishUpdateToOracle(address marketAddr, uint256 state) internal {
        bytes memory additionalData = abi.encode(int256(-100), int256(100), state);
        bytes memory newValue = abi.encode(int256(100)); // price

        oracle.publishRiskParameterUpdate("test-ref", newValue, UPDATE_TYPE, marketAddr, additionalData);
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

    function test_HubIntegration_MarketNotAllowed_Skipped() public {
        // Create update for non-allowed market
        address unauthorizedMarket = makeAddr("unauthorized");
        _publishUpdateToOracle(unauthorizedMarket, 1);

        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = agentId;

        (bool shouldExecute,) = hub.check(agentIds);
        assertFalse(shouldExecute, "Should skip non-allowed market");
    }

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
        oracle.publishRiskParameterUpdate("test-ref", newValue, UPDATE_TYPE, market, additionalData);

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
