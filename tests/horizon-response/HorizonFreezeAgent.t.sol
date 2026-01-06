// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { HorizonFreezeAgent } from "../../src/horizon-response/agents/HorizonFreezeAgent.sol";
import { BaseHorizonAgent } from "../../src/horizon-response/agents/BaseHorizonAgent.sol";
import { ILlamaGuardOracle } from "../../src/interfaces/ILlamaGuardOracle.sol";
import { MockPoolConfigurator } from "../mocks/MockPoolConfigurator.sol";

contract HorizonFreezeAgentTest is Test {
    HorizonFreezeAgent internal agent;
    MockPoolConfigurator internal poolConfigurator;

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
        agent = new HorizonFreezeAgent(agentHub);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Encode additionalData as (lowerBound, upperBound, state, supply)
    function _encodeAdditionalData(
        int256 lowerBound,
        int256 upperBound,
        uint256 state,
        uint256 supply
    )
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(lowerBound, upperBound, state, supply);
    }

    /// @dev Create a RiskParameterUpdate struct for testing
    function _createUpdate(
        address marketAddr,
        uint256 state,
        int256 lowerBound,
        int256 upperBound,
        uint256 supply
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
            additionalData: _encodeAdditionalData(lowerBound, upperBound, state, supply)
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
    // VALIDATE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Validate_ReturnsTrueForFrozenState() public view {
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(
            market,
            1, // state = FROZEN
            -100, // lowerBound
            100, // upperBound
            1000 // supply
        );

        bool isValid = agent.validate(0, "", update);
        assertTrue(isValid);
    }

    function test_Validate_ReturnsTrueForUnfrozenState() public view {
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(
            market,
            0, // state = UNFROZEN
            -100,
            100,
            1000
        );

        bool isValid = agent.validate(0, "", update);
        assertTrue(isValid);
    }

    function test_Validate_ReturnsFalseForInvalidState() public view {
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(
            market,
            2, // state = INVALID (> 1)
            -100,
            100,
            1000
        );

        bool isValid = agent.validate(0, "", update);
        assertFalse(isValid);
    }

    function test_Validate_ReturnsFalseForLargeState() public view {
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(
            market,
            999, // state = INVALID
            -100,
            100,
            1000
        );

        bool isValid = agent.validate(0, "", update);
        assertFalse(isValid);
    }

    function testFuzz_Validate_OnlyAcceptsZeroOrOne(uint256 state) public view {
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(market, state, -100, 100, 1000);

        bool isValid = agent.validate(0, "", update);

        if (state <= 1) {
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
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(market, 1, -100, 100, 1000);
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator));

        vm.prank(nonAgentHub);
        vm.expectRevert(abi.encodeWithSelector(BaseHorizonAgent.OnlyAgentHub.selector, nonAgentHub));
        agent.inject(0, agentContext, update);
    }

    function test_Inject_SucceedsWhenCalledByAgentHub() public {
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(market, 1, -100, 100, 1000);
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator));

        vm.prank(agentHub);
        agent.inject(0, agentContext, update);

        // Verify the freeze was executed
        assertTrue(poolConfigurator.isFrozen(market));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PROCESS UPDATE / FREEZE LOGIC TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_ProcessUpdate_FreezesReserveWhenStateIsOne() public {
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(
            market,
            1, // FROZEN
            -100,
            100,
            1000
        );
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator));

        vm.prank(agentHub);
        agent.inject(0, agentContext, update);

        assertTrue(poolConfigurator.isFrozen(market));
        assertEq(poolConfigurator.lastFreezeAsset(), market);
        assertTrue(poolConfigurator.lastFreezeState());
        assertEq(poolConfigurator.freezeCallCount(), 1);
    }

    function test_ProcessUpdate_UnfreezesReserveWhenStateIsZero() public {
        // First freeze the reserve
        ILlamaGuardOracle.RiskParameterUpdate memory freezeUpdate = _createUpdate(market, 1, -100, 100, 1000);
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator));

        vm.prank(agentHub);
        agent.inject(0, agentContext, freezeUpdate);
        assertTrue(poolConfigurator.isFrozen(market));

        // Now unfreeze
        ILlamaGuardOracle.RiskParameterUpdate memory unfreezeUpdate = _createUpdate(
            market,
            0, // UNFROZEN
            -100,
            100,
            1000
        );

        vm.prank(agentHub);
        agent.inject(0, agentContext, unfreezeUpdate);

        assertFalse(poolConfigurator.isFrozen(market));
        assertEq(poolConfigurator.lastFreezeAsset(), market);
        assertFalse(poolConfigurator.lastFreezeState());
        assertEq(poolConfigurator.freezeCallCount(), 2);
    }

    function test_ProcessUpdate_EmitsReserveFreezeUpdatedEvent() public {
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(market, 1, -100, 100, 1000);
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator));

        vm.prank(agentHub);
        vm.expectEmit(true, false, false, true);
        emit ReserveFreezeUpdated(market, true, 1);
        agent.inject(0, agentContext, update);
    }

    function test_ProcessUpdate_EmitsEventOnUnfreeze() public {
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(market, 0, -100, 100, 1000);
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator));

        vm.prank(agentHub);
        vm.expectEmit(true, false, false, true);
        emit ReserveFreezeUpdated(market, false, 0);
        agent.inject(0, agentContext, update);
    }

    function test_ProcessUpdate_HandlesMultipleMarkets() public {
        address market1 = makeAddr("market1");
        address market2 = makeAddr("market2");
        address market3 = makeAddr("market3");

        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator));

        // Freeze market1
        ILlamaGuardOracle.RiskParameterUpdate memory update1 = _createUpdate(market1, 1, -100, 100, 1000);
        vm.prank(agentHub);
        agent.inject(0, agentContext, update1);

        // Freeze market2
        ILlamaGuardOracle.RiskParameterUpdate memory update2 = _createUpdate(market2, 1, -200, 200, 2000);
        vm.prank(agentHub);
        agent.inject(0, agentContext, update2);

        // Unfreeze market3 (was never frozen, but should still work)
        ILlamaGuardOracle.RiskParameterUpdate memory update3 = _createUpdate(market3, 0, -300, 300, 3000);
        vm.prank(agentHub);
        agent.inject(0, agentContext, update3);

        assertTrue(poolConfigurator.isFrozen(market1));
        assertTrue(poolConfigurator.isFrozen(market2));
        assertFalse(poolConfigurator.isFrozen(market3));
        assertEq(poolConfigurator.freezeCallCount(), 3);
    }

    function test_ProcessUpdate_DecodesPoolConfiguratorFromContext() public {
        // Create a second pool configurator
        MockPoolConfigurator poolConfigurator2 = new MockPoolConfigurator();

        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(market, 1, -100, 100, 1000);

        // Use first configurator
        bytes memory agentContext1 = _encodeAgentContext(address(poolConfigurator));
        vm.prank(agentHub);
        agent.inject(0, agentContext1, update);

        assertTrue(poolConfigurator.isFrozen(market));
        assertFalse(poolConfigurator2.isFrozen(market));

        // Use second configurator for a different market
        address market2 = makeAddr("market2");
        ILlamaGuardOracle.RiskParameterUpdate memory update2 = _createUpdate(market2, 1, -100, 100, 1000);
        bytes memory agentContext2 = _encodeAgentContext(address(poolConfigurator2));

        vm.prank(agentHub);
        agent.inject(0, agentContext2, update2);

        assertFalse(poolConfigurator.isFrozen(market2));
        assertTrue(poolConfigurator2.isFrozen(market2));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADDITIONAL DATA DECODING TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_ProcessUpdate_DecodesAdditionalDataCorrectly(
        int256 lowerBound,
        int256 upperBound,
        uint256 supply
    )
        public
    {
        // Test with state = 1 (freeze)
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(market, 1, lowerBound, upperBound, supply);
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator));

        vm.prank(agentHub);
        agent.inject(0, agentContext, update);

        // Verify freeze was called regardless of other values
        assertTrue(poolConfigurator.isFrozen(market));
    }

    function testFuzz_ProcessUpdate_StateZeroUnfreezes(int256 lowerBound, int256 upperBound, uint256 supply) public {
        // Test with state = 0 (unfreeze)
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(market, 0, lowerBound, upperBound, supply);
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator));

        vm.prank(agentHub);
        agent.inject(0, agentContext, update);

        // Verify unfreeze was called
        assertFalse(poolConfigurator.isFrozen(market));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_ProcessUpdate_WithZeroAddress() public {
        address zeroMarket = address(0);
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(zeroMarket, 1, -100, 100, 1000);
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
            type(int256).max, // upperBound
            type(uint256).max // supply
        );
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator));

        vm.prank(agentHub);
        agent.inject(0, agentContext, update);

        assertTrue(poolConfigurator.isFrozen(market));
    }

    function test_ProcessUpdate_RepeatedFreezeIdemptotent() public {
        ILlamaGuardOracle.RiskParameterUpdate memory update = _createUpdate(market, 1, -100, 100, 1000);
        bytes memory agentContext = _encodeAgentContext(address(poolConfigurator));

        // Freeze multiple times
        vm.startPrank(agentHub);
        agent.inject(0, agentContext, update);
        agent.inject(0, agentContext, update);
        agent.inject(0, agentContext, update);
        vm.stopPrank();

        assertTrue(poolConfigurator.isFrozen(market));
        assertEq(poolConfigurator.freezeCallCount(), 3);
    }
}
