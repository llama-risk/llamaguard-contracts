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

    string[] internal defaultUpdateTypes;

    event ParameterUpdated(
        string referenceId,
        bytes newValue,
        bytes previousValue,
        uint256 timestamp,
        string indexed updateType,
        uint256 indexed updateId,
        address indexed market,
        bytes additionalData
    );

    event UpdateTypeAdded(string indexed updateType);

    function setUp() public {
        // Setup default update types
        defaultUpdateTypes = new string[](3);
        defaultUpdateTypes[0] = "price";
        defaultUpdateTypes[1] = "supply";
        defaultUpdateTypes[2] = "risk_state";

        oracle = new LlamaGuardOracle(8, "Test Feed", 1, defaultUpdateTypes);
    }

    function _encodeUpdateValue(uint256 supply_, int256 price_, uint256 state_) internal pure returns (bytes memory) {
        return abi.encode(supply_, price_, state_);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testConstructorInitialization() public view {
        assertEq(oracle.decimals(), 8);
        assertEq(oracle.description(), "Test Feed");
        assertEq(oracle.version(), 1);

        // Check initial update types
        string[] memory types = oracle.getAllUpdateTypes();
        assertEq(types.length, 3);
        assertEq(types[0], "price");
        assertEq(types[1], "supply");
        assertEq(types[2], "risk_state");
    }

    function testConstructorWithDifferentParameters() public {
        string[] memory customTypes = new string[](2);
        customTypes[0] = "custom_type";
        customTypes[1] = "another_type";

        LlamaGuardOracle newOracle = new LlamaGuardOracle(18, "ETH/USD", 2, customTypes);
        assertEq(newOracle.decimals(), 18);
        assertEq(newOracle.description(), "ETH/USD");
        assertEq(newOracle.version(), 2);

        string[] memory types = newOracle.getAllUpdateTypes();
        assertEq(types.length, 2);
        assertEq(types[0], "custom_type");
        assertEq(types[1], "another_type");
    }

    function testConstructorWithEmptyUpdateTypes() public {
        string[] memory emptyTypes = new string[](0);
        LlamaGuardOracle newOracle = new LlamaGuardOracle(8, "Test", 1, emptyTypes);
        string[] memory types = newOracle.getAllUpdateTypes();
        assertEq(types.length, 0);
    }

    function testConstructorRejectsInvalidUpdateTypeString() public {
        string[] memory invalidTypes = new string[](1);
        invalidTypes[0] = ""; // Empty string

        vm.expectRevert(abi.encodeWithSelector(ILlamaGuardOracle.InvalidUpdateTypeString.selector, ""));
        new LlamaGuardOracle(8, "Test", 1, invalidTypes);
    }

    function testConstructorRejectsTooLongUpdateTypeString() public {
        string[] memory invalidTypes = new string[](1);
        invalidTypes[0] = "this_is_a_very_long_string_that_exceeds_the_64_character_limit_for_update_types"; // > 64
        // chars

        vm.expectRevert(abi.encodeWithSelector(ILlamaGuardOracle.InvalidUpdateTypeString.selector, invalidTypes[0]));
        new LlamaGuardOracle(8, "Test", 1, invalidTypes);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // USER STORY 1: RELIABLE PRICE DATA ACCESS (AggregatorV3 Compatibility)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_US1_latestRoundData_ReturnsCurrentPrice() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        oracle.updateData("ref-1", _encodeUpdateValue(1000, 500, 2), "price", address(0), "");

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
        oracle.updateData("ref-1", _encodeUpdateValue(100, 50, 1), "price", address(0), "");
        oracle.updateData("ref-2", _encodeUpdateValue(200, 75, 2), "price", address(0), "");
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
        oracle.updateData("ref-1", _encodeUpdateValue(1000, 500, 1), "price", address(0), "");
        oracle.updateData("ref-2", _encodeUpdateValue(2000, 600, 2), "supply", address(0), "");
        oracle.updateData("ref-3", _encodeUpdateValue(3000, 700, 3), "risk_state", address(0), "");
        vm.stopPrank();

        // latestRoundData should return the latest price
        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, 700);
    }

    function testFuzz_US1_latestRoundData_ValidPriceRange(uint256 supply_, int256 price_, uint256 state_) public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        oracle.updateData("ref-1", abi.encode(supply_, price_, state_), "price", address(0), "");

        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, price_);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // USER STORY 2: RISK PARAMETER UPDATE HISTORY
    // ═══════════════════════════════════════════════════════════════════════════

    function test_US2_getUpdateById_ReturnsCompleteRecord() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        bytes memory newValue = _encodeUpdateValue(1000, 500, 2);
        address market = address(0x9999);
        bytes memory additionalData = "extra data";

        vm.prank(writer);
        oracle.updateData("reference-123", newValue, "price", market, additionalData);

        ILlamaGuardOracle.RiskParameterUpdate memory update = oracle.getUpdateById(2);

        assertEq(update.timestamp, block.timestamp);
        assertEq(update.newValue, newValue);
        assertEq(update.referenceId, "reference-123");
        assertEq(update.updateType, "price");
        assertEq(update.updateId, 2);
        assertEq(update.market, market);
        assertEq(update.additionalData, additionalData);
    }

    function test_US2_getUpdateById_PreviousValueTracking() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        bytes memory firstValue = _encodeUpdateValue(100, 50, 1);
        bytes memory secondValue = _encodeUpdateValue(200, 75, 2);

        vm.startPrank(writer);
        oracle.updateData("ref-1", firstValue, "price", address(0), "");
        oracle.updateData("ref-2", secondValue, "price", address(0), "");
        vm.stopPrank();

        // First update should have empty previousValue
        ILlamaGuardOracle.RiskParameterUpdate memory update1 = oracle.getUpdateById(2);
        assertEq(update1.previousValue.length, 0);

        // Second update should have first value as previousValue
        ILlamaGuardOracle.RiskParameterUpdate memory update2 = oracle.getUpdateById(3);
        assertEq(update2.previousValue, firstValue);
    }

    function test_US2_getUpdateById_ReferenceIdPreserved() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        oracle.updateData("my-unique-reference-id", _encodeUpdateValue(1000, 500, 2), "price", address(0), "");

        ILlamaGuardOracle.RiskParameterUpdate memory update = oracle.getUpdateById(2);
        assertEq(update.referenceId, "my-unique-reference-id");
    }

    function test_US2_RevertWhen_InvalidUpdateId() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        oracle.updateData("ref-1", _encodeUpdateValue(1000, 500, 2), "price", address(0), "");

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
        oracle.updateData("ref-1", _encodeUpdateValue(1000, 500, 2), "price", address(0), "");

        // Verify data was stored
        (uint256 supply, uint256 state, int256 price,) = oracle.getData();
        assertEq(supply, 1000);
        assertEq(state, 2);
        assertEq(price, 500);
    }

    function test_US3_RevertWhen_InvalidUpdateType() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        vm.expectRevert(abi.encodeWithSelector(ILlamaGuardOracle.UnauthorizedUpdateType.selector, "invalid_type"));
        oracle.updateData("ref-1", _encodeUpdateValue(1000, 500, 2), "invalid_type", address(0), "");
    }

    function test_US3_updateData_EmitsParameterUpdatedEvent() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        bytes memory newValue = _encodeUpdateValue(1000, 500, 2);
        bytes memory emptyPrevValue = "";
        address market = address(0x9999);
        bytes memory additionalData = "test";

        vm.prank(writer);
        vm.expectEmit(true, true, true, true);
        emit ParameterUpdated("ref-1", newValue, emptyPrevValue, block.timestamp, "price", 2, market, additionalData);
        oracle.updateData("ref-1", newValue, "price", market, additionalData);
    }

    function test_US3_RevertWhen_UnauthorizedCaller() public {
        vm.prank(nonWriter);
        vm.expectRevert();
        oracle.updateData("ref-1", _encodeUpdateValue(1000, 500, 2), "price", address(0), "");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // USER STORY 4: UPDATE TYPE MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    function test_US4_addUpdateType_OwnerSuccess() public {
        oracle.addUpdateType("new_custom_type");

        assertTrue(oracle.isValidUpdateType("new_custom_type"));

        string[] memory types = oracle.getAllUpdateTypes();
        assertEq(types.length, 4);
        assertEq(types[3], "new_custom_type");
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

    function test_US4_getAllUpdateTypes_ReturnsAllTypes() public {
        string[] memory types = oracle.getAllUpdateTypes();
        assertEq(types.length, 3);
        assertEq(types[0], "price");
        assertEq(types[1], "supply");
        assertEq(types[2], "risk_state");

        // Add a new type and verify
        oracle.addUpdateType("new_type");
        types = oracle.getAllUpdateTypes();
        assertEq(types.length, 4);
        assertEq(types[3], "new_type");
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
    // GETDATA TESTS (BACKWARD COMPATIBILITY)
    // ═══════════════════════════════════════════════════════════════════════════

    function testGetDataInitialState() public view {
        (uint256 s, uint256 st, int256 p, uint256 startedAt) = oracle.getData();
        assertEq(s, 0);
        assertEq(st, 0);
        assertEq(p, 0);
        assertGt(startedAt, 0);
    }

    function testGetDataAfterUpdate() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        uint256 beforeTs = block.timestamp;
        vm.prank(writer);
        oracle.updateData("ref-1", _encodeUpdateValue(5000, 2500, 7), "price", address(0), "");
        (uint256 s, uint256 st, int256 p, uint256 startedAt) = oracle.getData();
        assertEq(s, 5000);
        assertEq(st, 7);
        assertEq(p, 2500);
        assertGe(startedAt, beforeTs);
    }

    function testGetDataCallableByAnyone() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        vm.prank(writer);
        oracle.updateData("ref-1", _encodeUpdateValue(1000, 500, 2), "price", address(0), "");

        vm.prank(nonWriter);
        (uint256 s1, uint256 st1, int256 p1,) = oracle.getData();
        vm.prank(admin);
        (uint256 s2, uint256 st2, int256 p2,) = oracle.getData();
        vm.prank(address(0xABCD));
        (uint256 s3, uint256 st3, int256 p3,) = oracle.getData();

        assertEq(s1, 1000);
        assertEq(s2, 1000);
        assertEq(s3, 1000);
        assertEq(st1, 2);
        assertEq(st2, 2);
        assertEq(st3, 2);
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
        oracle.updateData("ref-1", _encodeUpdateValue(1000, 500, 2), "price", address(0), "");
        uint80 newId = oracle.getLatestRoundId();
        assertEq(newId, initialId + 1);
    }

    function testAggregatorStoresMultipleRounds() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        vm.startPrank(writer);
        oracle.updateData("ref-1", _encodeUpdateValue(100, 50, 1), "price", address(0), "");
        uint80 r1 = oracle.getLatestRoundId();
        oracle.updateData("ref-2", _encodeUpdateValue(200, 75, 2), "price", address(0), "");
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
        oracle.updateData("ref-1", _encodeUpdateValue(1000, 500, 2), "price", address(0), "");
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
                string(abi.encodePacked("ref-", vm.toString(i))),
                _encodeUpdateValue(i * 100, int256(i * 50), i),
                "price",
                address(0),
                ""
            );
        }
        vm.stopPrank();

        (uint256 s, uint256 st, int256 p,) = oracle.getData();
        assertEq(s, 1000);
        assertEq(st, 10);
        assertEq(p, 500);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzzUpdateData(uint256 _supply, int256 _price, uint256 _state) public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        vm.prank(writer);
        oracle.updateData("ref-1", abi.encode(_supply, _price, _state), "price", address(0), "");

        (uint256 s, uint256 st, int256 p,) = oracle.getData();
        assertEq(s, _supply);
        assertEq(st, _state);
        assertEq(p, _price);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // USER STORY 5: QUERY LATEST UPDATE BY PARAMETER AND MARKET (002 FEATURE)
    // ═══════════════════════════════════════════════════════════════════════════

    // ----- US2: Index Tracking Tests (T005-T007) -----

    function test_UpdateData_UpdatesLatestIndex() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        address market = address(0x1111);

        vm.prank(writer);
        oracle.updateData("ref-1", _encodeUpdateValue(1000, 500, 2), "price", market, "");

        // The index should now point to updateId 2 (first update after roundId 1)
        ILlamaGuardOracle.RiskParameterUpdate memory update =
            oracle.getLatestUpdateByParameterAndMarket("price", market);

        assertEq(update.updateId, 2);
        assertEq(update.market, market);
        assertEq(update.updateType, "price");
    }

    function test_UpdateData_OverwritesPreviousIndex() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        address market = address(0x2222);

        vm.startPrank(writer);
        // First update
        oracle.updateData("ref-1", _encodeUpdateValue(100, 50, 1), "price", market, "");
        uint256 firstUpdateId = oracle.getLatestRoundId();

        // Second update for same (type, market) pair
        oracle.updateData("ref-2", _encodeUpdateValue(200, 75, 2), "price", market, "");
        uint256 secondUpdateId = oracle.getLatestRoundId();
        vm.stopPrank();

        // Index should point to the latest update
        ILlamaGuardOracle.RiskParameterUpdate memory update =
            oracle.getLatestUpdateByParameterAndMarket("price", market);

        assertEq(update.updateId, secondUpdateId);
        assertGt(update.updateId, firstUpdateId);
        assertEq(update.referenceId, "ref-2");
    }

    function test_UpdateData_IndependentIndexPerPair() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        address market1 = address(0x3333);
        address market2 = address(0x4444);

        vm.startPrank(writer);
        // Update for (price, market1)
        oracle.updateData("ref-1", _encodeUpdateValue(100, 50, 1), "price", market1, "");
        uint256 priceMarket1Id = oracle.getLatestRoundId();

        // Update for (price, market2)
        oracle.updateData("ref-2", _encodeUpdateValue(200, 75, 2), "price", market2, "");
        uint256 priceMarket2Id = oracle.getLatestRoundId();

        // Update for (supply, market1)
        oracle.updateData("ref-3", _encodeUpdateValue(300, 100, 3), "supply", market1, "");
        uint256 supplyMarket1Id = oracle.getLatestRoundId();
        vm.stopPrank();

        // Each (type, market) pair should have independent tracking
        ILlamaGuardOracle.RiskParameterUpdate memory update1 =
            oracle.getLatestUpdateByParameterAndMarket("price", market1);
        ILlamaGuardOracle.RiskParameterUpdate memory update2 =
            oracle.getLatestUpdateByParameterAndMarket("price", market2);
        ILlamaGuardOracle.RiskParameterUpdate memory update3 =
            oracle.getLatestUpdateByParameterAndMarket("supply", market1);

        assertEq(update1.updateId, priceMarket1Id);
        assertEq(update2.updateId, priceMarket2Id);
        assertEq(update3.updateId, supplyMarket1Id);

        // Verify each points to correct reference
        assertEq(update1.referenceId, "ref-1");
        assertEq(update2.referenceId, "ref-2");
        assertEq(update3.referenceId, "ref-3");
    }

    // ----- US1: Query Function Tests (T011-T015) -----

    function test_GetLatestUpdateByParameterAndMarket_ReturnsCorrectUpdate() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        address market = address(0x5555);
        bytes memory newValue = _encodeUpdateValue(1000, 500, 2);
        bytes memory additionalData = "test data";

        vm.prank(writer);
        oracle.updateData("reference-123", newValue, "price", market, additionalData);

        ILlamaGuardOracle.RiskParameterUpdate memory update =
            oracle.getLatestUpdateByParameterAndMarket("price", market);

        assertEq(update.timestamp, block.timestamp);
        assertEq(update.newValue, newValue);
        assertEq(update.referenceId, "reference-123");
        assertEq(update.updateType, "price");
        assertEq(update.market, market);
        assertEq(update.additionalData, additionalData);
    }

    function test_GetLatestUpdateByParameterAndMarket_ReturnsLatestAfterMultipleUpdates() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        address market = address(0x6666);

        vm.startPrank(writer);
        oracle.updateData("ref-1", _encodeUpdateValue(100, 50, 1), "price", market, "");
        oracle.updateData("ref-2", _encodeUpdateValue(200, 75, 2), "price", market, "");
        oracle.updateData("ref-3", _encodeUpdateValue(300, 100, 3), "price", market, "");
        vm.stopPrank();

        ILlamaGuardOracle.RiskParameterUpdate memory update =
            oracle.getLatestUpdateByParameterAndMarket("price", market);

        // Should return the latest (third) update
        assertEq(update.referenceId, "ref-3");
        (uint256 supply,,) = abi.decode(update.newValue, (uint256, int256, uint256));
        assertEq(supply, 300);
    }

    function test_GetLatestUpdateByParameterAndMarket_ReturnsEmptyForNonExistent() public view {
        // Query for a (type, market) pair that has no updates
        ILlamaGuardOracle.RiskParameterUpdate memory update =
            oracle.getLatestUpdateByParameterAndMarket("price", address(0x9999));

        // Should return empty struct with timestamp = 0
        assertEq(update.timestamp, 0);
        assertEq(update.updateId, 0);
        assertEq(update.market, address(0));
        assertEq(bytes(update.updateType).length, 0);
        assertEq(bytes(update.referenceId).length, 0);
        assertEq(update.newValue.length, 0);
    }

    function test_GetLatestUpdateByParameterAndMarket_DoesNotRevert() public view {
        // Per FR-005: System MUST NOT revert when querying for non-existent combinations
        // This test verifies no revert occurs for various non-existent queries
        oracle.getLatestUpdateByParameterAndMarket("price", address(0x1));
        oracle.getLatestUpdateByParameterAndMarket("nonexistent_type", address(0x2));
        oracle.getLatestUpdateByParameterAndMarket("", address(0x3));
        oracle.getLatestUpdateByParameterAndMarket("supply", address(0));

        // If we reach here, no reverts occurred
        assertTrue(true);
    }

    function test_GetLatestUpdateByParameterAndMarket_WorksWithAddressZero() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        // address(0) is valid for global/non-market-specific updates per FR-006
        vm.prank(writer);
        oracle.updateData("global-ref", _encodeUpdateValue(1000, 500, 2), "price", address(0), "");

        ILlamaGuardOracle.RiskParameterUpdate memory update =
            oracle.getLatestUpdateByParameterAndMarket("price", address(0));

        assertEq(update.market, address(0));
        assertEq(update.referenceId, "global-ref");
        assertGt(update.timestamp, 0);
    }

    // ----- Fuzz Test (T021) -----

    function testFuzz_GetLatestUpdateByParameterAndMarket(
        uint8 updateTypeIndex,
        address market,
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
        oracle.updateData("fuzz-ref", abi.encode(supply, price, state), updateType, market, "");

        ILlamaGuardOracle.RiskParameterUpdate memory update =
            oracle.getLatestUpdateByParameterAndMarket(updateType, market);

        // Verify correct update is returned
        assertEq(update.market, market);
        assertEq(update.updateType, updateType);
        assertEq(update.referenceId, "fuzz-ref");
        assertGt(update.timestamp, 0);

        // Decode and verify values
        (uint256 returnedSupply, int256 returnedPrice, uint256 returnedState) =
            abi.decode(update.newValue, (uint256, int256, uint256));
        assertEq(returnedSupply, supply);
        assertEq(returnedPrice, price);
        assertEq(returnedState, state);
    }

    // ----- US3: Interface Consistency Tests (T018) -----

    function test_InterfaceConsistency_GetLatestUpdateByParameterAndMarket() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        address market = address(0x7777);

        vm.prank(writer);
        oracle.updateData("ref-interface", _encodeUpdateValue(1000, 500, 2), "price", market, "");

        // Call via interface to verify signature compatibility
        ILlamaGuardOracle iOracle = ILlamaGuardOracle(address(oracle));
        ILlamaGuardOracle.RiskParameterUpdate memory update =
            iOracle.getLatestUpdateByParameterAndMarket("price", market);

        assertEq(update.referenceId, "ref-interface");
        assertEq(update.market, market);
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
}
