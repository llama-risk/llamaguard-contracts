// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { LlamaGuardOracleTestBase } from "./LlamaGuardOracleTestBase.sol";
import { LlamaGuardOracle } from "../src/LlamaGuardOracle.sol";
import { ILlamaGuardOracle } from "../src/interfaces/ILlamaGuardOracle.sol";

/// @title LlamaGuardOracleTest
/// @notice Core tests for LlamaGuardOracle - constructor, US1 (price data), US2 (update history)
contract LlamaGuardOracleTest is LlamaGuardOracleTestBase {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testConstructorInitialization() public view {
        assertEq(oracle.decimals(), 8);
        assertEq(oracle.description(), "Test Feed");
        assertEq(oracle.version(), 1);

        // Check initial update types via public array access
        assertEq(oracle.updateTypes(0), PRICE_TYPE);
        assertEq(oracle.updateTypes(1), SUPPLY_TYPE);
        assertEq(oracle.updateTypes(2), RISK_STATE_TYPE);
        assertEq(oracle.updateTypes(3), BOUNDED_NAV_TYPE);
        assertTrue(oracle.isValidUpdateType(PRICE_TYPE));
        assertTrue(oracle.isValidUpdateType(SUPPLY_TYPE));
        assertTrue(oracle.isValidUpdateType(RISK_STATE_TYPE));
        assertTrue(oracle.isValidUpdateType(BOUNDED_NAV_TYPE));
    }

    function testConstructorWithDifferentParameters() public {
        string[] memory customTypes = new string[](2);
        customTypes[0] = "custom_type";
        customTypes[1] = "another_type";

        address[] memory noMarkets = new address[](0);
        LlamaGuardOracle newOracle = new LlamaGuardOracle(18, "ETH/USD", 2, customTypes, noMarkets);
        assertEq(newOracle.decimals(), 18);
        assertEq(newOracle.description(), "ETH/USD");
        assertEq(newOracle.version(), 2);

        // Check update types via public array access
        assertEq(newOracle.updateTypes(0), customTypes[0]);
        assertEq(newOracle.updateTypes(1), customTypes[1]);
        assertTrue(newOracle.isValidUpdateType(customTypes[0]));
        assertTrue(newOracle.isValidUpdateType(customTypes[1]));
    }

    function testConstructorWithEmptyUpdateTypes() public {
        string[] memory emptyTypes = new string[](0);
        address[] memory noMarkets = new address[](0);
        LlamaGuardOracle newOracle = new LlamaGuardOracle(8, "Test", 1, emptyTypes, noMarkets);

        // Verify no valid update types exist by checking that common types are invalid
        assertFalse(newOracle.isValidUpdateType(PRICE_TYPE));
        assertFalse(newOracle.isValidUpdateType(SUPPLY_TYPE));

        // Verify accessing updateTypes(0) reverts for empty array
        vm.expectRevert();
        newOracle.updateTypes(0);
    }

    function testConstructorRejectsInvalidUpdateTypeString() public {
        string[] memory invalidTypes = new string[](1);
        invalidTypes[0] = ""; // Empty string

        address[] memory noMarkets = new address[](0);
        vm.expectRevert(abi.encodeWithSelector(ILlamaGuardOracle.InvalidUpdateTypeString.selector, ""));
        new LlamaGuardOracle(8, "Test", 1, invalidTypes, noMarkets);
    }

    function testConstructorRejectsTooLongUpdateTypeString() public {
        string[] memory invalidTypes = new string[](1);
        invalidTypes[0] = "this_is_a_very_long_string_that_exceeds_the_64_character_limit_for_update_types"; // > 64
        // chars

        address[] memory noMarkets = new address[](0);
        vm.expectRevert(abi.encodeWithSelector(ILlamaGuardOracle.InvalidUpdateTypeString.selector, invalidTypes[0]));
        new LlamaGuardOracle(8, "Test", 1, invalidTypes, noMarkets);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // USER STORY 1: RELIABLE PRICE DATA ACCESS (AggregatorV3 Compatibility)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_US1_latestRoundData_ReturnsCurrentPrice() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_TYPE, 1000, 2));

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracle.latestRoundData();

        assertEq(roundId, 1);
        assertEq(answer, 500);
        assertGt(startedAt, 0);
        assertGt(updatedAt, 0);
        assertEq(answeredInRound, 1);
    }

    function test_US1_getRoundData_ReturnsHistoricalPrice() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.startPrank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 50, PRICE_TYPE, 100, 1));
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", 75, PRICE_TYPE, 200, 2));
        vm.stopPrank();

        // Check historical round
        (, int256 answer1,,,) = oracle.getRoundData(1);
        assertEq(answer1, 50);

        // Check latest round
        (, int256 answer2,,,) = oracle.getRoundData(2);
        assertEq(answer2, 75);
    }

    function test_US1_latestRoundData_IndependentOfRiskDataState() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        // Even with different updateTypes, price data should always be accessible
        vm.startPrank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_TYPE, 1000, 1));
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", 600, SUPPLY_TYPE, 2000, 2));
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-3", 700, RISK_STATE_TYPE, 3000, 3));
        vm.stopPrank();

        // latestRoundData should return the latest price
        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, 700);
    }

    function testFuzz_US1_latestRoundData_ValidPriceRange(uint256 supply_, int256 price_, uint256 state_) public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", price_, PRICE_TYPE, supply_, state_));

        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, price_);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // USER STORY 2: RISK PARAMETER UPDATE HISTORY
    // ═══════════════════════════════════════════════════════════════════════════

    function test_US2_getUpdateById_ReturnsCompleteRecord() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        bytes memory newValue = _encodePrice(500);
        bytes memory additionalData = _encodeAdditionalData(1000, 500, 2);

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("reference-123", 500, PRICE_TYPE, 1000, 2));

        ILlamaGuardOracle.RiskParameterUpdate memory update = oracle.getUpdateById(1);

        assertEq(update.timestamp, block.timestamp);
        assertEq(update.newValue, newValue);
        assertEq(update.referenceId, "reference-123");
        assertEq(keccak256(bytes(update.updateType)), priceHash);
        assertEq(update.updateId, 1);
        // Market is now always address(0) in stored updates
        assertEq(update.market, address(0));
        assertEq(update.additionalData, additionalData);
    }

    function test_US2_getUpdateById_PreviousValueTracking() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        bytes memory firstPrice = _encodePrice(50);

        vm.startPrank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 50, PRICE_TYPE, 100, 1));
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", 75, PRICE_TYPE, 200, 2));
        vm.stopPrank();

        // First update should have empty previousValue
        ILlamaGuardOracle.RiskParameterUpdate memory update1 = oracle.getUpdateById(1);
        assertEq(update1.previousValue.length, 0);

        // Second update should have first price as previousValue
        ILlamaGuardOracle.RiskParameterUpdate memory update2 = oracle.getUpdateById(2);
        assertEq(update2.previousValue, firstPrice);
    }

    function test_US2_getUpdateById_ReferenceIdPreserved() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("my-unique-reference-id", 500, PRICE_TYPE, 1000, 2));

        ILlamaGuardOracle.RiskParameterUpdate memory update = oracle.getUpdateById(1);
        assertEq(update.referenceId, "my-unique-reference-id");
    }

    function test_US2_RevertWhen_InvalidUpdateId() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_TYPE, 1000, 2));

        // ID 0 should revert
        vm.expectRevert(abi.encodeWithSelector(ILlamaGuardOracle.InvalidUpdateId.selector, 0));
        oracle.getUpdateById(0);

        // ID > latest should revert
        vm.expectRevert(abi.encodeWithSelector(ILlamaGuardOracle.InvalidUpdateId.selector, 999));
        oracle.getUpdateById(999);
    }
}
