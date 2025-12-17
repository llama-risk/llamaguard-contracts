// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { LlamaGuardOracle } from "../src/LlamaGuardOracle.sol";
import { ILlamaGuardOracle } from "../src/interfaces/ILlamaGuardOracle.sol";

contract LlamaGuardOracleTest is Test {
    LlamaGuardOracle internal oracle;

    address internal admin = address(this);
    address internal writer = address(0x1234);
    address internal nonWriter = address(0x5678);

    // Default test market for legacy tests (markets added in Phase 3)
    address internal defaultMarket = address(0xDEFA);

    string[] internal defaultUpdateTypes;

    event ParameterUpdated(
        string referenceId,
        bytes newValue,
        bytes previousValue,
        uint256 timestamp,
        string indexed updateType,
        uint256 indexed updateId,
        bytes additionalData
    );

    event UpdateTypeAdded(string indexed updateType);

    function setUp() public {
        // Setup default update types
        defaultUpdateTypes = new string[](3);
        defaultUpdateTypes[0] = "price";
        defaultUpdateTypes[1] = "supply";
        defaultUpdateTypes[2] = "risk_state";

        // Create initial authorized markets array with defaultMarket for legacy tests
        address[] memory initialMarkets = new address[](1);
        initialMarkets[0] = defaultMarket;
        oracle = new LlamaGuardOracle(8, "Test Feed", 1, defaultUpdateTypes, initialMarkets);
    }

    /// @dev Encode price for newValue parameter (just price for Chainlink compatibility)
    function _encodePrice(int256 price_) internal pure returns (bytes memory) {
        return abi.encode(price_);
    }

    /// @dev Encode full bundle for additionalData parameter (supply, price, state)
    function _encodeAdditionalData(uint256 supply_, int256 price_, uint256 state_)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(supply_, price_, state_);
    }

    /// @dev Create UpdateInput struct for updateData calls
    function _createUpdateInput(
        string memory referenceId,
        int256 price_,
        string memory updateType,
        uint256 supply_,
        uint256 state_
    )
        internal
        pure
        returns (ILlamaGuardOracle.UpdateInput memory)
    {
        return ILlamaGuardOracle.UpdateInput({
            referenceId: referenceId,
            newValue: abi.encode(price_),
            updateType: updateType,
            additionalData: abi.encode(supply_, price_, state_)
        });
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testConstructorInitialization() public view {
        assertEq(oracle.decimals(), 8);
        assertEq(oracle.description(), "Test Feed");
        assertEq(oracle.version(), 1);

        // Check initial update types via public array access
        assertEq(oracle.updateTypes(0), "price");
        assertEq(oracle.updateTypes(1), "supply");
        assertEq(oracle.updateTypes(2), "risk_state");
        assertTrue(oracle.isValidUpdateType("price"));
        assertTrue(oracle.isValidUpdateType("supply"));
        assertTrue(oracle.isValidUpdateType("risk_state"));
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
        assertEq(newOracle.updateTypes(0), "custom_type");
        assertEq(newOracle.updateTypes(1), "another_type");
        assertTrue(newOracle.isValidUpdateType("custom_type"));
        assertTrue(newOracle.isValidUpdateType("another_type"));
    }

    function testConstructorWithEmptyUpdateTypes() public {
        string[] memory emptyTypes = new string[](0);
        address[] memory noMarkets = new address[](0);
        LlamaGuardOracle newOracle = new LlamaGuardOracle(8, "Test", 1, emptyTypes, noMarkets);
        // Verify no valid update types exist by checking that common types are invalid
        assertFalse(newOracle.isValidUpdateType("price"));
        assertFalse(newOracle.isValidUpdateType("supply"));
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
        oracle.updateData(_createUpdateInput("ref-1", 500, "price", 1000, 2));

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracle.latestRoundData();

        assertEq(roundId, 2);
        assertEq(answer, 500);
        assertGt(startedAt, 0);
        assertGt(updatedAt, 0);
        assertEq(answeredInRound, 2);
    }

    function test_US1_getRoundData_ReturnsHistoricalPrice() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.startPrank(writer);
        oracle.updateData(_createUpdateInput("ref-1", 50, "price", 100, 1));
        oracle.updateData(_createUpdateInput("ref-2", 75, "price", 200, 2));
        vm.stopPrank();

        // Check historical round
        (, int256 answer1,,,) = oracle.getRoundData(2);
        assertEq(answer1, 50);

        // Check latest round
        (, int256 answer2,,,) = oracle.getRoundData(3);
        assertEq(answer2, 75);
    }

    function test_US1_latestRoundData_IndependentOfRiskDataState() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        // Even with different updateTypes, price data should always be accessible
        vm.startPrank(writer);
        oracle.updateData(_createUpdateInput("ref-1", 500, "price", 1000, 1));
        oracle.updateData(_createUpdateInput("ref-2", 600, "supply", 2000, 2));
        oracle.updateData(_createUpdateInput("ref-3", 700, "risk_state", 3000, 3));
        vm.stopPrank();

        // latestRoundData should return the latest price
        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, 700);
    }

    function testFuzz_US1_latestRoundData_ValidPriceRange(uint256 supply_, int256 price_, uint256 state_) public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        oracle.updateData(_createUpdateInput("ref-1", price_, "price", supply_, state_));

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
        oracle.updateData(_createUpdateInput("reference-123", 500, "price", 1000, 2));

        ILlamaGuardOracle.RiskParameterUpdate memory update = oracle.getUpdateById(2);

        assertEq(update.timestamp, block.timestamp);
        assertEq(update.newValue, newValue);
        assertEq(update.referenceId, "reference-123");
        assertEq(update.updateType, "price");
        assertEq(update.updateId, 2);
        // Market is now always address(0) in stored updates
        assertEq(update.market, address(0));
        assertEq(update.additionalData, additionalData);
    }

    function test_US2_getUpdateById_PreviousValueTracking() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        bytes memory firstPrice = _encodePrice(50);

        vm.startPrank(writer);
        oracle.updateData(_createUpdateInput("ref-1", 50, "price", 100, 1));
        oracle.updateData(_createUpdateInput("ref-2", 75, "price", 200, 2));
        vm.stopPrank();

        // First update should have empty previousValue
        ILlamaGuardOracle.RiskParameterUpdate memory update1 = oracle.getUpdateById(2);
        assertEq(update1.previousValue.length, 0);

        // Second update should have first price as previousValue
        ILlamaGuardOracle.RiskParameterUpdate memory update2 = oracle.getUpdateById(3);
        assertEq(update2.previousValue, firstPrice);
    }

    function test_US2_getUpdateById_ReferenceIdPreserved() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        oracle.updateData(_createUpdateInput("my-unique-reference-id", 500, "price", 1000, 2));

        ILlamaGuardOracle.RiskParameterUpdate memory update = oracle.getUpdateById(2);
        assertEq(update.referenceId, "my-unique-reference-id");
    }

    function test_US2_RevertWhen_InvalidUpdateId() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        oracle.updateData(_createUpdateInput("ref-1", 500, "price", 1000, 2));

        // ID 0 should revert
        vm.expectRevert(abi.encodeWithSelector(ILlamaGuardOracle.InvalidUpdateId.selector, 0));
        oracle.getUpdateById(0);

        // ID > latest should revert
        vm.expectRevert(abi.encodeWithSelector(ILlamaGuardOracle.InvalidUpdateId.selector, 999));
        oracle.getUpdateById(999);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // USER STORY 3: AUTHORIZED DATA UPDATES WITH TYPE VALIDATION
    // ═══════════════════════════════════════════════════════════════════════════

    function test_US3_updateData_ValidTypeAccepted() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        oracle.updateData(_createUpdateInput("ref-1", 500, "price", 1000, 2));

        // Verify data was stored via latestRoundData
        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, 500);

        // Also verify via getUpdateById - decode from additionalData for full bundle
        ILlamaGuardOracle.RiskParameterUpdate memory update = oracle.getUpdateById(2);
        (uint256 supply, int256 price, uint256 state) = abi.decode(update.additionalData, (uint256, int256, uint256));
        assertEq(supply, 1000);
        assertEq(state, 2);
        assertEq(price, 500);
    }

    function test_US3_RevertWhen_InvalidUpdateType() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        vm.expectRevert(abi.encodeWithSelector(ILlamaGuardOracle.UnauthorizedUpdateType.selector, "invalid_type"));
        oracle.updateData(_createUpdateInput("ref-1", 500, "invalid_type", 1000, 2));
    }

    function test_US3_updateData_EmitsParameterUpdatedEvent() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        bytes memory newValue = _encodePrice(500);
        bytes memory emptyPrevValue = "";
        bytes memory additionalData = _encodeAdditionalData(1000, 500, 2);

        vm.prank(writer);
        vm.expectEmit(true, true, true, true);
        emit ParameterUpdated("ref-1", newValue, emptyPrevValue, block.timestamp, "price", 2, additionalData);
        oracle.updateData(_createUpdateInput("ref-1", 500, "price", 1000, 2));
    }

    function test_US3_RevertWhen_UnauthorizedCaller() public {
        vm.prank(nonWriter);
        vm.expectRevert();
        oracle.updateData(_createUpdateInput("ref-1", 500, "price", 1000, 2));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // USER STORY 4: UPDATE TYPE MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    function test_US4_addUpdateType_OwnerSuccess() public {
        oracle.addUpdateType("new_custom_type");

        assertTrue(oracle.isValidUpdateType("new_custom_type"));

        // Verify new type is at index 3 via public array access
        assertEq(oracle.updateTypes(3), "new_custom_type");
    }

    function test_US4_addUpdateType_EmitsUpdateTypeAddedEvent() public {
        vm.expectEmit(true, false, false, true);
        emit UpdateTypeAdded("new_type");
        oracle.addUpdateType("new_type");
    }

    function test_US4_RevertWhen_DuplicateUpdateType() public {
        vm.expectRevert(abi.encodeWithSelector(ILlamaGuardOracle.UpdateTypeAlreadyExists.selector, "price"));
        oracle.addUpdateType("price");
    }

    function test_US4_RevertWhen_InvalidUpdateTypeString() public {
        // Empty string
        vm.expectRevert(abi.encodeWithSelector(ILlamaGuardOracle.InvalidUpdateTypeString.selector, ""));
        oracle.addUpdateType("");

        // Too long string (> 64 chars)
        string memory longString = "this_is_a_very_long_string_that_exceeds_the_64_character_limit_for_update_types";
        vm.expectRevert(abi.encodeWithSelector(ILlamaGuardOracle.InvalidUpdateTypeString.selector, longString));
        oracle.addUpdateType(longString);
    }

    function test_US4_updateTypesArrayAccess_ReturnsAllTypes() public {
        // Verify initial types via public array access
        assertEq(oracle.updateTypes(0), "price");
        assertEq(oracle.updateTypes(1), "supply");
        assertEq(oracle.updateTypes(2), "risk_state");

        // Add a new type and verify it's appended
        oracle.addUpdateType("new_type");
        assertEq(oracle.updateTypes(3), "new_type");
        assertTrue(oracle.isValidUpdateType("new_type"));
    }

    function test_US4_RevertWhen_NonOwnerAddsType() public {
        vm.prank(nonWriter);
        vm.expectRevert();
        oracle.addUpdateType("new_type");
    }

    function test_US4_isValidUpdateType() public view {
        assertTrue(oracle.isValidUpdateType("price"));
        assertTrue(oracle.isValidUpdateType("supply"));
        assertTrue(oracle.isValidUpdateType("risk_state"));
        assertFalse(oracle.isValidUpdateType("invalid"));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LATESTROUND DATA TESTS (BACKWARD COMPATIBILITY)
    // ═══════════════════════════════════════════════════════════════════════════

    function testLatestRoundDataInitialState() public view {
        (, int256 answer, uint256 startedAt,,) = oracle.latestRoundData();
        assertEq(answer, 0);
        assertGt(startedAt, 0);
    }

    function testLatestRoundDataAfterUpdate() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        uint256 beforeTs = block.timestamp;
        vm.prank(writer);
        oracle.updateData(_createUpdateInput("ref-1", 2500, "price", 5000, 7));
        (, int256 answer, uint256 startedAt,,) = oracle.latestRoundData();
        assertEq(answer, 2500);
        assertGe(startedAt, beforeTs);
    }

    function testLatestRoundDataCallableByAnyone() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        vm.prank(writer);
        oracle.updateData(_createUpdateInput("ref-1", 500, "price", 1000, 2));

        vm.prank(nonWriter);
        (, int256 p1,,,) = oracle.latestRoundData();
        vm.prank(admin);
        (, int256 p2,,,) = oracle.latestRoundData();
        vm.prank(address(0xABCD));
        (, int256 p3,,,) = oracle.latestRoundData();

        assertEq(p1, 500);
        assertEq(p2, 500);
        assertEq(p3, 500);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // AGGREGATOR INTEGRATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testAggregatorRoundIdIncreases() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        uint80 initialId = oracle.getLatestRoundId();
        vm.prank(writer);
        oracle.updateData(_createUpdateInput("ref-1", 500, "price", 1000, 2));
        uint80 newId = oracle.getLatestRoundId();
        assertEq(newId, initialId + 1);
    }

    function testAggregatorStoresMultipleRounds() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        vm.startPrank(writer);
        oracle.updateData(_createUpdateInput("ref-1", 50, "price", 100, 1));
        uint80 r1 = oracle.getLatestRoundId();
        oracle.updateData(_createUpdateInput("ref-2", 75, "price", 200, 2));
        uint80 r2 = oracle.getLatestRoundId();
        vm.stopPrank();

        (, int256 p1,,,) = oracle.getRoundData(r1);
        (, int256 p2,,,) = oracle.getRoundData(r2);
        assertEq(p1, 50);
        assertEq(p2, 75);
    }

    function testOracleIsChainlinkAggregator() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        vm.prank(writer);
        oracle.updateData(_createUpdateInput("ref-1", 500, "price", 1000, 2));
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracle.latestRoundData();
        assertEq(answer, 500);
        assertGt(roundId, 0);
        assertGt(startedAt, 0);
        assertGt(updatedAt, 0);
        assertGt(answeredInRound, 0);
    }

    function testSequentialUpdatesInSameTransaction() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        vm.startPrank(writer);
        for (uint256 i = 1; i <= 10; i++) {
            oracle.updateData(
                _createUpdateInput(
                    string(abi.encodePacked("ref-", vm.toString(i))), int256(i * 50), "price", i * 100, i
                )
            );
        }
        vm.stopPrank();

        // Verify via latestRoundData
        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, 500);

        // Verify full data via getUpdateById - decode from additionalData for full bundle
        ILlamaGuardOracle.RiskParameterUpdate memory update = oracle.getUpdateById(11); // 10th update, roundId starts
        // at 1
        (uint256 supply, int256 price, uint256 state) = abi.decode(update.additionalData, (uint256, int256, uint256));
        assertEq(supply, 1000);
        assertEq(state, 10);
        assertEq(price, 500);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzzUpdateData(uint256 _supply, int256 _price, uint256 _state) public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        vm.prank(writer);
        oracle.updateData(_createUpdateInput("ref-1", _price, "price", _supply, _state));

        // Verify price via latestRoundData
        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, _price);

        // Verify full data via getUpdateById - decode from additionalData for full bundle
        ILlamaGuardOracle.RiskParameterUpdate memory update = oracle.getUpdateById(2);
        (uint256 supply, int256 price, uint256 state) = abi.decode(update.additionalData, (uint256, int256, uint256));
        assertEq(supply, _supply);
        assertEq(state, _state);
        assertEq(price, _price);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // USER STORY 5: QUERY LATEST UPDATE BY PARAMETER AND MARKET (002 FEATURE)
    // ═══════════════════════════════════════════════════════════════════════════

    // ----- US2: Index Tracking Tests (T005-T007) -----
    // NOTE: After refactoring, updates are tracked by updateType only (not by market).
    // The market parameter in getLatestUpdateByParameterAndMarket is now rewritten to the returned struct.

    function test_UpdateData_UpdatesLatestIndex() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        address queryMarket = address(0x1111);

        vm.prank(writer);
        oracle.updateData(_createUpdateInput("ref-1", 500, "price", 1000, 2));

        // The index should now point to updateId 2 (first update after roundId 1)
        // Query with any market - the market will be rewritten to the input value
        ILlamaGuardOracle.RiskParameterUpdate memory update =
            oracle.getLatestUpdateByParameterAndMarket("price", queryMarket);

        assertEq(update.updateId, 2);
        // Market is rewritten to the query parameter
        assertEq(update.market, queryMarket);
        assertEq(update.updateType, "price");
    }

    function test_UpdateData_OverwritesPreviousIndex() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        address queryMarket = address(0x2222);

        vm.startPrank(writer);
        // First update
        oracle.updateData(_createUpdateInput("ref-1", 50, "price", 100, 1));
        uint256 firstUpdateId = oracle.getLatestRoundId();

        // Second update for same type
        oracle.updateData(_createUpdateInput("ref-2", 75, "price", 200, 2));
        uint256 secondUpdateId = oracle.getLatestRoundId();
        vm.stopPrank();

        // Index should point to the latest update
        ILlamaGuardOracle.RiskParameterUpdate memory update =
            oracle.getLatestUpdateByParameterAndMarket("price", queryMarket);

        assertEq(update.updateId, secondUpdateId);
        assertGt(update.updateId, firstUpdateId);
        assertEq(update.referenceId, "ref-2");
    }

    function test_UpdateData_IndependentIndexPerUpdateType() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        address queryMarket = address(0x3333);

        vm.startPrank(writer);
        // Update for price type
        oracle.updateData(_createUpdateInput("ref-1", 50, "price", 100, 1));
        uint256 priceUpdateId = oracle.getLatestRoundId();

        // Update for supply type
        oracle.updateData(_createUpdateInput("ref-2", 75, "supply", 200, 2));
        uint256 supplyUpdateId = oracle.getLatestRoundId();

        // Update for risk_state type
        oracle.updateData(_createUpdateInput("ref-3", 100, "risk_state", 300, 3));
        uint256 riskStateUpdateId = oracle.getLatestRoundId();
        vm.stopPrank();

        // Each updateType should have independent tracking
        ILlamaGuardOracle.RiskParameterUpdate memory update1 =
            oracle.getLatestUpdateByParameterAndMarket("price", queryMarket);
        ILlamaGuardOracle.RiskParameterUpdate memory update2 =
            oracle.getLatestUpdateByParameterAndMarket("supply", queryMarket);
        ILlamaGuardOracle.RiskParameterUpdate memory update3 =
            oracle.getLatestUpdateByParameterAndMarket("risk_state", queryMarket);

        assertEq(update1.updateId, priceUpdateId);
        assertEq(update2.updateId, supplyUpdateId);
        assertEq(update3.updateId, riskStateUpdateId);

        // Verify each points to correct reference
        assertEq(update1.referenceId, "ref-1");
        assertEq(update2.referenceId, "ref-2");
        assertEq(update3.referenceId, "ref-3");

        // All queries return the same queryMarket (rewritten)
        assertEq(update1.market, queryMarket);
        assertEq(update2.market, queryMarket);
        assertEq(update3.market, queryMarket);
    }

    // ----- US1: Query Function Tests (T011-T015) -----

    function test_GetLatestUpdateByParameterAndMarket_ReturnsCorrectUpdate() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        address queryMarket = address(0x5555);
        bytes memory newValue = _encodePrice(500);
        bytes memory additionalData = _encodeAdditionalData(1000, 500, 2);

        vm.prank(writer);
        oracle.updateData(_createUpdateInput("reference-123", 500, "price", 1000, 2));

        ILlamaGuardOracle.RiskParameterUpdate memory update =
            oracle.getLatestUpdateByParameterAndMarket("price", queryMarket);

        assertEq(update.timestamp, block.timestamp);
        assertEq(update.newValue, newValue);
        assertEq(update.referenceId, "reference-123");
        assertEq(update.updateType, "price");
        // Market is rewritten to query parameter
        assertEq(update.market, queryMarket);
        assertEq(update.additionalData, additionalData);
    }

    function test_GetLatestUpdateByParameterAndMarket_ReturnsLatestAfterMultipleUpdates() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        address queryMarket = address(0x6666);

        vm.startPrank(writer);
        oracle.updateData(_createUpdateInput("ref-1", 50, "price", 100, 1));
        oracle.updateData(_createUpdateInput("ref-2", 75, "price", 200, 2));
        oracle.updateData(_createUpdateInput("ref-3", 100, "price", 300, 3));
        vm.stopPrank();

        ILlamaGuardOracle.RiskParameterUpdate memory update =
            oracle.getLatestUpdateByParameterAndMarket("price", queryMarket);

        // Should return the latest (third) update
        assertEq(update.referenceId, "ref-3");
        // Decode from additionalData for full bundle
        (uint256 supply,,) = abi.decode(update.additionalData, (uint256, int256, uint256));
        assertEq(supply, 300);
    }

    function test_GetLatestUpdateByParameterAndMarket_ReturnsEmptyForNonExistentType() public view {
        // Query for an updateType that has no updates
        ILlamaGuardOracle.RiskParameterUpdate memory update =
            oracle.getLatestUpdateByParameterAndMarket("nonexistent_type", address(0x9999));

        // Should return empty struct with timestamp = 0
        assertEq(update.timestamp, 0);
        assertEq(update.updateId, 0);
        assertEq(update.market, address(0));
        assertEq(bytes(update.updateType).length, 0);
        assertEq(bytes(update.referenceId).length, 0);
        assertEq(update.newValue.length, 0);
    }

    function test_GetLatestUpdateByParameterAndMarket_DoesNotRevert() public view {
        // Per FR-005: System MUST NOT revert when querying for non-existent update types
        // This test verifies no revert occurs for various queries
        oracle.getLatestUpdateByParameterAndMarket("price", address(0x1));
        oracle.getLatestUpdateByParameterAndMarket("nonexistent_type", address(0x2));
        oracle.getLatestUpdateByParameterAndMarket("", address(0x3));
        oracle.getLatestUpdateByParameterAndMarket("supply", address(0));

        // If we reach here, no reverts occurred
        assertTrue(true);
    }

    function test_GetLatestUpdateByParameterAndMarket_MarketIsRewritten() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        oracle.updateData(_createUpdateInput("market-ref", 500, "price", 1000, 2));

        // Query with different market addresses - market should be rewritten to query param
        address queryMarket1 = address(0x1111);
        address queryMarket2 = address(0x2222);

        ILlamaGuardOracle.RiskParameterUpdate memory update1 =
            oracle.getLatestUpdateByParameterAndMarket("price", queryMarket1);
        ILlamaGuardOracle.RiskParameterUpdate memory update2 =
            oracle.getLatestUpdateByParameterAndMarket("price", queryMarket2);

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

        string memory updateType;
        if (updateTypeIndex == 0) {
            updateType = "price";
        } else if (updateTypeIndex == 1) {
            updateType = "supply";
        } else {
            updateType = "risk_state";
        }

        vm.prank(writer);
        oracle.updateData(_createUpdateInput("fuzz-ref", price, updateType, supply, state));

        ILlamaGuardOracle.RiskParameterUpdate memory update =
            oracle.getLatestUpdateByParameterAndMarket(updateType, queryMarket);

        // Verify correct update is returned with market rewritten to query param
        assertEq(update.market, queryMarket);
        assertEq(update.updateType, updateType);
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

        address queryMarket = address(0x7777);

        vm.prank(writer);
        oracle.updateData(_createUpdateInput("ref-interface", 500, "price", 1000, 2));

        // Call via interface to verify signature compatibility
        ILlamaGuardOracle iOracle = ILlamaGuardOracle(address(oracle));
        ILlamaGuardOracle.RiskParameterUpdate memory update =
            iOracle.getLatestUpdateByParameterAndMarket("price", queryMarket);

        assertEq(update.referenceId, "ref-interface");
        // Market is rewritten to query param
        assertEq(update.market, queryMarket);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ACCESS CONTROL TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testHasWriteAccess() public {
        assertFalse(oracle.hasWriteAccess(writer));

        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        assertTrue(oracle.hasWriteAccess(writer));
        assertFalse(oracle.hasWriteAccess(nonWriter));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARKET AUTHORIZATION MANAGEMENT TESTS
    // ═══════════════════════════════════════════════════════════════════════════
    // NOTE: Market authorization is no longer used in updateData, but the management
    // functions (addAuthorizedMarket, removeAuthorizedMarket, isAuthorizedMarket)
    // are still available for external use cases.

    // Helper variables for market authorization tests
    address internal market1 = address(0x1111);
    address internal market2 = address(0x2222);
    address internal unauthorizedMarket = address(0x9999);

    // T014: test_Constructor_InitializesAuthorizedMarkets
    function test_Constructor_InitializesAuthorizedMarkets() public {
        // Arrange: Create markets array
        address[] memory initialMarkets = new address[](2);
        initialMarkets[0] = market1;
        initialMarkets[1] = market2;

        // Act: Deploy new oracle with initial markets
        LlamaGuardOracle newOracle = new LlamaGuardOracle(8, "Test", 1, defaultUpdateTypes, initialMarkets);

        // Assert: Markets are authorized
        assertTrue(newOracle.isAuthorizedMarket(market1));
        assertTrue(newOracle.isAuthorizedMarket(market2));
        assertFalse(newOracle.isAuthorizedMarket(unauthorizedMarket));
    }

    // T015: test_Constructor_EmitsAuthMarketAddedEvents
    function test_Constructor_EmitsAuthMarketAddedEvents() public {
        // Arrange: Create markets array
        address[] memory initialMarkets = new address[](2);
        initialMarkets[0] = market1;
        initialMarkets[1] = market2;

        // Act & Assert: Expect events for each market
        vm.expectEmit(true, false, false, false);
        emit ILlamaGuardOracle.AuthorizedMarketAdded(market1);
        vm.expectEmit(true, false, false, false);
        emit ILlamaGuardOracle.AuthorizedMarketAdded(market2);
        new LlamaGuardOracle(8, "Test", 1, defaultUpdateTypes, initialMarkets);
    }

    // T016: test_RevertWhen_Constructor_AddressZeroInArray
    function test_RevertWhen_Constructor_AddressZeroInArray() public {
        // Arrange: Create markets array with address(0)
        address[] memory initialMarkets = new address[](2);
        initialMarkets[0] = market1;
        initialMarkets[1] = address(0);

        // Act & Assert: Constructor reverts with InvalidMarketAddress
        vm.expectRevert(abi.encodeWithSelector(ILlamaGuardOracle.InvalidMarketAddress.selector, address(0)));
        new LlamaGuardOracle(8, "Test", 1, defaultUpdateTypes, initialMarkets);
    }

    // T017: test_Constructor_HandlesDuplicateMarkets
    function test_Constructor_HandlesDuplicateMarkets() public {
        // Arrange: Create markets array with duplicates
        address[] memory initialMarkets = new address[](3);
        initialMarkets[0] = market1;
        initialMarkets[1] = market2;
        initialMarkets[2] = market1; // Duplicate

        // Act: Deploy oracle (should not revert)
        LlamaGuardOracle newOracle = new LlamaGuardOracle(8, "Test", 1, defaultUpdateTypes, initialMarkets);

        // Assert: Market1 is authorized (idempotent)
        assertTrue(newOracle.isAuthorizedMarket(market1));
        assertTrue(newOracle.isAuthorizedMarket(market2));
    }
}
