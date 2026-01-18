// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { HorizonFreezeAgentTestBase } from "./HorizonFreezeAgentTestBase.sol";
import { HorizonFreezeAgent } from "../../src/horizon-response/agents/HorizonFreezeAgent.sol";
import { ILlamaGuardOracle } from "../../src/interfaces/ILlamaGuardOracle.sol";

/// @title HorizonFreezeAgentTest
/// @notice Unit tests for HorizonFreezeAgent - constructor, validate, and getMarkets
contract HorizonFreezeAgentTest is HorizonFreezeAgentTestBase {
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
}
