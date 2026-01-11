// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { HorizonFreezeAgent } from "../../src/horizon-response/agents/HorizonFreezeAgent.sol";
import { BaseHorizonAgent } from "../../src/horizon-response/agents/BaseHorizonAgent.sol";
import { ILlamaGuardOracle } from "../../src/interfaces/ILlamaGuardOracle.sol";
import { MockPoolConfigurator } from "../mocks/MockPoolConfigurator.sol";
import { MockPoolDataProvider } from "../mocks/MockPoolDataProvider.sol";

contract HorizonFreezeAgentTest is Test {
    HorizonFreezeAgent internal agent;
    MockPoolConfigurator internal poolConfigurator;
    MockPoolDataProvider internal poolDataProvider;

    address internal agentHub;
    address internal market;
    address internal nonAgentHub;

    event ReserveFreezeUpdated(address indexed market, bool frozen, uint256 state);

    bytes32 internal constant BOUNDED_NAV_HASH = keccak256(bytes("boundedNAV"));

    function setUp() public {
        agentHub = makeAddr("agentHub");
        market = makeAddr("market");
        nonAgentHub = makeAddr("nonAgentHub");

        poolConfigurator = new MockPoolConfigurator();
        poolDataProvider = new MockPoolDataProvider();
        agent = new HorizonFreezeAgent(agentHub);
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
            updateTypeHash: BOUNDED_NAV_HASH,
            updateId: 1,
            market: marketAddr,
            additionalData: _encodeAdditionalData(lowerBound, upperBound, state)
        });
    }

    /// @dev Encode agent context with pool configurator and pool data provider addresses
    function _encodeAgentContext(
        address poolConfiguratorAddr,
        address poolDataProviderAddr
    )
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(poolConfiguratorAddr, poolDataProviderAddr);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Constructor_SetsAgentHub() public view {
        assertEq(agent.AGENT_HUB(), agentHub);
    }

    function test_Constructor_DifferentAgentHub() public {
        address differentHub = makeAddr("differentHub");
        HorizonFreezeAgent newAgent = new HorizonFreezeAgent(differentHub);
        assertEq(newAgent.AGENT_HUB(), differentHub);
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
        // Market is not frozen in poolDataProvider by default
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(
            market,
            1, // state = FROZEN
            -100, // lowerBound
            100 // upperBound
        );
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator), address(poolDataProvider));

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
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator), address(poolDataProvider));

        bool isValid = agent.validate(0, agentContext, update);
        assertFalse(isValid);
    }

    function test_Validate_ReturnsFalseWhenAlreadyFrozen() public {
        // Set market as already frozen in poolDataProvider
        poolDataProvider.setFrozen(market, true);

        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(
            market,
            1, // state = FROZEN
            -100,
            100
        );
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator), address(poolDataProvider));

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
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator), address(poolDataProvider));

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
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator), address(poolDataProvider));

        bool isValid = agent.validate(0, agentContext, update);
        assertFalse(isValid);
    }

    function testFuzz_Validate_OnlyAcceptsFreezeWhenNotFrozen(uint256 state) public view {
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(market, state, -100, 100);
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator), address(poolDataProvider));

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

    function test_GetMarkets_ReturnsEmptyArray() public view {
        address[] memory markets = agent.getMarkets(0);
        assertEq(markets.length, 0);
    }

    function test_GetMarkets_ReturnsEmptyForAnyAgentId() public view {
        address[] memory markets1 = agent.getMarkets(0);
        address[] memory markets2 = agent.getMarkets(1);
        address[] memory markets3 = agent.getMarkets(type(uint256).max);

        assertEq(markets1.length, 0);
        assertEq(markets2.length, 0);
        assertEq(markets3.length, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INJECT ACCESS CONTROL TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Inject_RevertsWhenCalledByNonAgentHub() public {
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(market, 1, -100, 100);
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator), address(poolDataProvider));

        vm.prank(nonAgentHub);
        vm.expectRevert(abi.encodeWithSelector(BaseHorizonAgent.OnlyAgentHub.selector, nonAgentHub));
        agent.inject(0, agentContext, update);
    }

    function test_Inject_SucceedsWhenCalledByAgentHub() public {
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(market, 1, -100, 100);
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator), address(poolDataProvider));

        vm.prank(agentHub);
        agent.inject(0, agentContext, update);

        // Verify the freeze was executed
        assertTrue(poolConfigurator.isFrozen(market));
    }

    function test_Inject_RevertsWhenValidationFails() public {
        // Set market as already frozen - validation should fail
        poolDataProvider.setFrozen(market, true);

        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(market, 1, -100, 100);
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator), address(poolDataProvider));

        vm.prank(agentHub);
        vm.expectRevert(HorizonFreezeAgent.ValidationFailed.selector);
        agent.inject(0, agentContext, update);
    }

    function test_Inject_RevertsForUnfreezeState() public {
        // Try to unfreeze - should fail validation
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(market, 0, -100, 100);
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator), address(poolDataProvider));

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
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator), address(poolDataProvider));

        vm.prank(agentHub);
        agent.inject(0, agentContext, update);

        assertTrue(poolConfigurator.isFrozen(market));
        assertEq(poolConfigurator.lastFreezeAsset(), market);
        assertTrue(poolConfigurator.lastFreezeState());
        assertEq(poolConfigurator.freezeCallCount(), 1);
    }

    function test_ProcessUpdate_EmitsReserveFreezeUpdatedEvent() public {
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(market, 1, -100, 100);
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator), address(poolDataProvider));

        vm.prank(agentHub);
        vm.expectEmit(true, false, false, true);
        emit ReserveFreezeUpdated(market, true, 1);
        agent.inject(0, agentContext, update);
    }

    function test_ProcessUpdate_HandlesMultipleMarkets() public {
        address market1 = makeAddr("market1");
        address market2 = makeAddr("market2");

        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator), address(poolDataProvider));

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
        bytes memory agentContext1 = _encodeAgentContext(address(poolConfigurator), address(poolDataProvider));
        vm.prank(agentHub);
        agent.inject(0, agentContext1, update);

        assertTrue(poolConfigurator.isFrozen(market));
        assertFalse(poolConfigurator2.isFrozen(market));

        // Use second configurator for a different market
        address market2 = makeAddr("market2");
        ILlamaGuardOracle.RiskParameterUpdate memory update2 = _createUpdate(market2, 1, -100, 100);
        bytes memory agentContext2 = _encodeAgentContext(address(poolConfigurator2), address(poolDataProvider));

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
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator), address(poolDataProvider));

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
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator), address(poolDataProvider));

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
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator), address(poolDataProvider));

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
        // Also mark it as frozen in poolDataProvider (what we query)
        poolDataProvider.setFrozen(market, true);

        // Try to unfreeze via oracle - should fail
        ILlamaGuardOracle.RiskParameterUpdate memory unfreezeUpdate = _createUpdate(market, 0, -100, 100);
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator), address(poolDataProvider));

        vm.prank(agentHub);
        vm.expectRevert(HorizonFreezeAgent.ValidationFailed.selector);
        agent.inject(0, agentContext, unfreezeUpdate);

        // Market should still be frozen
        assertTrue(poolConfigurator.isFrozen(market));
    }

    function test_CannotDoubleFreezeViaOracle() public {
        // First freeze the market
        ILlamaGuardOracle.RiskParameterUpdate memory freezeUpdate = _createUpdate(market, 1, -100, 100);
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator), address(poolDataProvider));

        vm.prank(agentHub);
        agent.inject(0, agentContext, freezeUpdate);

        // Now mark it as frozen in poolDataProvider (simulating sync)
        poolDataProvider.setFrozen(market, true);

        // Try to freeze again - should fail validation
        vm.prank(agentHub);
        vm.expectRevert(HorizonFreezeAgent.ValidationFailed.selector);
        agent.inject(0, agentContext, freezeUpdate);
    }
}
