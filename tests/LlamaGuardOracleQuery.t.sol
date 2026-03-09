// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { LlamaGuardOracleTestBase } from "./LlamaGuardOracleTestBase.sol";
import { ILlamaGuardOracle } from "../src/interfaces/ILlamaGuardOracle.sol";

/// @title LlamaGuardOracleQueryTest
/// @notice Query, interface consistency, and AggregatorV2 tests for LlamaGuardOracle
contract LlamaGuardOracleQueryTest is LlamaGuardOracleTestBase {
    // ═══════════════════════════════════════════════════════════════════════════
    // USER STORY 5: QUERY LATEST UPDATE BY PARAMETER AND MARKET (002 FEATURE)
    // ═══════════════════════════════════════════════════════════════════════════

    // ----- US2: Index Tracking Tests (T005-T007) -----
    // NOTE: After refactoring, updates are tracked by updateType only (not by market).
    // The market parameter in getLatestUpdateByParameterAndMarket is now rewritten to the returned struct.

    function test_UpdateData_UpdatesLatestIndex() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_TYPE, 1000, 2));

        // The index should now point to updateId 1 (first update)
        // Query with authorized market - the market will be rewritten to the input value
        ILlamaGuardOracle.RiskParameterUpdate memory update =
            oracle.getLatestUpdateByParameterAndMarket(PRICE_TYPE, defaultMarket);

        assertEq(update.updateId, 1);
        // Market is rewritten to the query parameter
        assertEq(update.market, defaultMarket);
        assertEq(keccak256(bytes(update.updateType)), priceHash);
    }

    function test_UpdateData_OverwritesPreviousIndex() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.startPrank(writer);
        // First update
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 50, PRICE_TYPE, 100, 1));
        uint256 firstUpdateId = oracle.getLatestRoundId();

        // Second update for same type
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", 75, PRICE_TYPE, 200, 2));
        uint256 secondUpdateId = oracle.getLatestRoundId();
        vm.stopPrank();

        // Index should point to the latest update
        ILlamaGuardOracle.RiskParameterUpdate memory update =
            oracle.getLatestUpdateByParameterAndMarket(PRICE_TYPE, defaultMarket);

        assertEq(update.updateId, secondUpdateId);
        assertGt(update.updateId, firstUpdateId);
        assertEq(update.referenceId, "ref-2");
    }

    function test_UpdateData_IndependentIndexPerUpdateType() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.startPrank(writer);
        // Update for price type
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 50, PRICE_TYPE, 100, 1));
        uint256 priceUpdateId = oracle.getLatestRoundId();

        // Update for supply type
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", 75, SUPPLY_TYPE, 200, 2));
        uint256 supplyUpdateId = oracle.getLatestRoundId();

        // Update for risk_state type
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-3", 100, RISK_STATE_TYPE, 300, 3));
        uint256 riskStateUpdateId = oracle.getLatestRoundId();
        vm.stopPrank();

        // Each updateType should have independent tracking (using bytes32 overload)
        ILlamaGuardOracle.RiskParameterUpdate memory update1 =
            oracle.getLatestUpdateByParameterAndMarket(PRICE_TYPE, defaultMarket);
        ILlamaGuardOracle.RiskParameterUpdate memory update2 =
            oracle.getLatestUpdateByParameterAndMarket(SUPPLY_TYPE, defaultMarket);
        ILlamaGuardOracle.RiskParameterUpdate memory update3 =
            oracle.getLatestUpdateByParameterAndMarket(RISK_STATE_TYPE, defaultMarket);

        assertEq(update1.updateId, priceUpdateId);
        assertEq(update2.updateId, supplyUpdateId);
        assertEq(update3.updateId, riskStateUpdateId);

        // Verify each points to correct reference
        assertEq(update1.referenceId, "ref-1");
        assertEq(update2.referenceId, "ref-2");
        assertEq(update3.referenceId, "ref-3");

        // All queries return the same defaultMarket (rewritten)
        assertEq(update1.market, defaultMarket);
        assertEq(update2.market, defaultMarket);
        assertEq(update3.market, defaultMarket);
    }

    // ----- US1: Query Function Tests (T011-T015) -----

    function test_GetLatestUpdateByParameterAndMarket_ReturnsCorrectUpdate() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        bytes memory newValue = _encodePrice(500);
        bytes memory additionalData = _encodeAdditionalData(1000, 500, 2);

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("reference-123", 500, PRICE_TYPE, 1000, 2));

        ILlamaGuardOracle.RiskParameterUpdate memory update =
            oracle.getLatestUpdateByParameterAndMarket(PRICE_TYPE, defaultMarket);

        assertEq(update.timestamp, block.timestamp);
        assertEq(update.newValue, newValue);
        assertEq(update.referenceId, "reference-123");
        assertEq(keccak256(bytes(update.updateType)), priceHash);
        // Market is rewritten to query parameter
        assertEq(update.market, defaultMarket);
        assertEq(update.additionalData, additionalData);
    }

    function test_GetLatestUpdateByParameterAndMarket_ReturnsLatestAfterMultipleUpdates() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.startPrank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 50, PRICE_TYPE, 100, 1));
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", 75, PRICE_TYPE, 200, 2));
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-3", 100, PRICE_TYPE, 300, 3));
        vm.stopPrank();

        ILlamaGuardOracle.RiskParameterUpdate memory update =
            oracle.getLatestUpdateByParameterAndMarket(PRICE_TYPE, defaultMarket);

        // Should return the latest (third) update
        assertEq(update.referenceId, "ref-3");
        // Decode from additionalData for full bundle
        (uint256 supply,,) = abi.decode(update.additionalData, (uint256, int256, uint256));
        assertEq(supply, 300);
    }

    function test_GetLatestUpdateByParameterAndMarket_RevertsForNonExistentType() public {
        // Query for an updateType that has no updates should revert with InvalidUpdateId(0)
        // Note: Must use authorized market; unauthorized market reverts first
        string memory nonExistentType = "nonexistent_type";
        vm.expectRevert(abi.encodeWithSelector(ILlamaGuardOracle.InvalidUpdateId.selector, 0));
        oracle.getLatestUpdateByParameterAndMarket(nonExistentType, defaultMarket);
    }

    function test_GetLatestUpdateByParameterAndMarket_RevertsForTypeWithNoUpdates() public {
        // Even valid update types should revert if they have no updates yet
        // priceHash is valid but has no updates
        // Note: Must use authorized market; unauthorized market reverts first
        vm.expectRevert(abi.encodeWithSelector(ILlamaGuardOracle.InvalidUpdateId.selector, 0));
        oracle.getLatestUpdateByParameterAndMarket(PRICE_TYPE, defaultMarket);
    }

    function test_GetLatestUpdateByParameterAndMarket_MarketIsRewritten() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("market-ref", 500, PRICE_TYPE, 1000, 2));

        // Query with different authorized market addresses - market should be rewritten to query param
        address queryMarket1 = address(0x1111);
        address queryMarket2 = address(0x2222);

        // Authorize both markets
        oracle.addAuthorizedMarket(queryMarket1);
        oracle.addAuthorizedMarket(queryMarket2);

        ILlamaGuardOracle.RiskParameterUpdate memory update1 =
            oracle.getLatestUpdateByParameterAndMarket(PRICE_TYPE, queryMarket1);
        ILlamaGuardOracle.RiskParameterUpdate memory update2 =
            oracle.getLatestUpdateByParameterAndMarket(PRICE_TYPE, queryMarket2);

        // Same update data, different market in response
        assertEq(update1.market, queryMarket1);
        assertEq(update2.market, queryMarket2);
        assertEq(update1.referenceId, "market-ref");
        assertEq(update2.referenceId, "market-ref");
        assertGt(update1.timestamp, 0);
        assertGt(update2.timestamp, 0);
    }

    // ----- Fuzz Test (T021) -----

    function testFuzz_GetLatestUpdateByParameterAndMarket(
        uint8 updateTypeIndex,
        address queryMarket,
        uint256 supply,
        int256 price,
        uint256 state
    )
        public
    {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        // Bound updateTypeIndex to valid range (0-2 for our 3 default types)
        updateTypeIndex = uint8(bound(updateTypeIndex, 0, 2));

        // Ensure queryMarket is valid (non-zero) and authorize it if not already
        vm.assume(queryMarket != address(0));
        // fuzzing sometimes tries to add the same market twice, to prevent this we check if the market is already
        // authorized
        if (!oracle.isAuthorizedMarket(queryMarket)) {
            oracle.addAuthorizedMarket(queryMarket);
        }

        string memory updateType;
        if (updateTypeIndex == 0) {
            updateType = PRICE_TYPE;
        } else if (updateTypeIndex == 1) {
            updateType = SUPPLY_TYPE;
        } else {
            updateType = RISK_STATE_TYPE;
        }

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("fuzz-ref", price, updateType, supply, state));

        // Query using string updateType
        ILlamaGuardOracle.RiskParameterUpdate memory update =
            oracle.getLatestUpdateByParameterAndMarket(updateType, queryMarket);

        // Verify correct update is returned with market rewritten to query param
        assertEq(update.market, queryMarket);
        assertEq(keccak256(bytes(update.updateType)), keccak256(bytes(updateType)));
        assertEq(update.referenceId, "fuzz-ref");
        assertGt(update.timestamp, 0);

        // Decode and verify values from additionalData (full bundle)
        (uint256 returnedSupply, int256 returnedPrice, uint256 returnedState) =
            abi.decode(update.additionalData, (uint256, int256, uint256));
        assertEq(returnedSupply, supply);
        assertEq(returnedPrice, price);
        assertEq(returnedState, state);
    }

    // ----- US3: Interface Consistency Tests (T018) -----

    function test_InterfaceConsistency_GetLatestUpdateByParameterAndMarket() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-interface", 500, PRICE_TYPE, 1000, 2));

        // Call via interface to verify signature compatibility
        ILlamaGuardOracle iOracle = ILlamaGuardOracle(address(oracle));
        ILlamaGuardOracle.RiskParameterUpdate memory update =
            iOracle.getLatestUpdateByParameterAndMarket(PRICE_TYPE, defaultMarket);

        assertEq(update.referenceId, "ref-interface");
        // Market is rewritten to query param
        assertEq(update.market, defaultMarket);
    }

    function test_InterfaceConsistency_GetLatestUpdateByParameterAndMarket_StringOverload() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        string memory updateType = "price";

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-string", 600, PRICE_TYPE, 2000, 3));

        // Call via interface using string overload with explicit string memory variable
        ILlamaGuardOracle iOracle = ILlamaGuardOracle(address(oracle));
        ILlamaGuardOracle.RiskParameterUpdate memory update =
            iOracle.getLatestUpdateByParameterAndMarket(updateType, defaultMarket);

        assertEq(update.referenceId, "ref-string");
        assertEq(update.market, defaultMarket);
        assertEq(keccak256(bytes(update.updateType)), priceHash);
    }

    function test_StringQuery_ReturnsCorrectData() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-compare", 700, PRICE_TYPE, 3000, 4));

        // Query using string updateType
        ILlamaGuardOracle.RiskParameterUpdate memory update =
            oracle.getLatestUpdateByParameterAndMarket(PRICE_TYPE, defaultMarket);

        assertEq(update.referenceId, "ref-compare");
        assertEq(keccak256(bytes(update.updateType)), keccak256(bytes(PRICE_TYPE)));
        assertEq(update.market, defaultMarket);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // AGGREGATOR V2 INTERFACE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_V2_latestAnswer_ReturnsCurrentPrice() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_TYPE, 1000, 2));

        assertEq(oracle.latestAnswer(), 500);
    }

    function test_V2_latestAnswer_ReturnsZeroInitially() public view {
        assertEq(oracle.latestAnswer(), 0);
    }

    function test_V2_latestTimestamp_ReturnsBlockTimestamp() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        uint256 beforeTs = block.timestamp;
        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_TYPE, 1000, 2));

        assertGe(oracle.latestTimestamp(), beforeTs);
    }

    function test_V2_latestTimestamp_ReturnsZeroInitially() public view {
        assertEq(oracle.latestTimestamp(), 0);
    }

    function test_V2_latestRound_ReturnsRoundIdAsUint256() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_TYPE, 1000, 2));

        assertEq(oracle.latestRound(), 1);
    }

    function test_V2_latestRound_ReturnsZeroInitially() public view {
        assertEq(oracle.latestRound(), 0);
    }

    function test_V2_getAnswer_ReturnsHistoricalPrice() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.startPrank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 50, PRICE_TYPE, 100, 1));
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", 75, PRICE_TYPE, 200, 2));
        vm.stopPrank();

        assertEq(oracle.getAnswer(1), 50);
        assertEq(oracle.getAnswer(2), 75);
    }

    function test_V2_getTimestamp_ReturnsHistoricalTimestamp() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.warp(1000);
        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 50, PRICE_TYPE, 100, 1));

        vm.warp(2000);
        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", 75, PRICE_TYPE, 200, 2));

        assertEq(oracle.getTimestamp(1), 1000);
        assertEq(oracle.getTimestamp(2), 2000);
    }

    function test_V2_AnswerUpdatedEvent_EmittedOnUpdate() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        vm.expectEmit(true, true, false, true);
        emit AnswerUpdated(500, 1, block.timestamp);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_TYPE, 1000, 2));
    }

    function test_V2_NewRoundEvent_EmittedOnUpdate() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        vm.expectEmit(true, true, false, true);
        emit NewRound(1, writer, block.timestamp);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_TYPE, 1000, 2));
    }

    function testFuzz_V2_latestAnswer_MatchesLatestRoundData(int256 price_) public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", price_, PRICE_TYPE, 1000, 2));

        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(oracle.latestAnswer(), answer);
    }

    function testFuzz_V2_latestTimestamp_MatchesLatestRoundData(uint256 warpTime) public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        warpTime = bound(warpTime, 1, type(uint128).max);
        vm.warp(warpTime);

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_TYPE, 1000, 2));

        (,,, uint256 updatedAt,) = oracle.latestRoundData();
        assertEq(oracle.latestTimestamp(), updatedAt);
    }
}
