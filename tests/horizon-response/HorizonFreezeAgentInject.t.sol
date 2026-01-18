// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { HorizonFreezeAgentTestBase } from "./HorizonFreezeAgentTestBase.sol";
import { HorizonFreezeAgent } from "../../src/horizon-response/agents/HorizonFreezeAgent.sol";
import { BaseHorizonAgent } from "../../src/horizon-response/agents/BaseHorizonAgent.sol";
import { ILlamaGuardOracle } from "../../src/interfaces/ILlamaGuardOracle.sol";
import { MockPoolConfigurator } from "../mocks/MockPoolConfigurator.sol";

/// @title HorizonFreezeAgentInjectTest
/// @notice Tests for HorizonFreezeAgent inject, process update, and security
contract HorizonFreezeAgentInjectTest is HorizonFreezeAgentTestBase {
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
