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

    // Pre-computed hashes for commonly used update types
    bytes32 internal constant PRICE_HASH = keccak256(bytes("price"));
    bytes32 internal constant SUPPLY_HASH = keccak256(bytes("supply"));
    bytes32 internal constant RISK_STATE_HASH = keccak256(bytes("risk_state"));

    event ParameterUpdated(
        string referenceId,
        bytes newValue,
        bytes previousValue,
        uint256 timestamp,
        bytes32 indexed updateTypeHash,
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

    /// @dev Create UpdateInput struct for updateLatestRiskRoundData calls
    function _createUpdateInput(
        string memory referenceId,
        int256 price_,
        bytes32 updateTypeHash,
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
            updateTypeHash: updateTypeHash,
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
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_HASH, 1000, 2));

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
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 50, PRICE_HASH, 100, 1));
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", 75, PRICE_HASH, 200, 2));
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
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_HASH, 1000, 1));
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", 600, SUPPLY_HASH, 2000, 2));
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-3", 700, RISK_STATE_HASH, 3000, 3));
        vm.stopPrank();

        // latestRoundData should return the latest price
        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, 700);
    }

    function testFuzz_US1_latestRoundData_ValidPriceRange(uint256 supply_, int256 price_, uint256 state_) public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", price_, PRICE_HASH, supply_, state_));

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
        oracle.updateLatestRiskRoundData(_createUpdateInput("reference-123", 500, PRICE_HASH, 1000, 2));

        ILlamaGuardOracle.RiskParameterUpdate memory update = oracle.getUpdateById(1);

        assertEq(update.timestamp, block.timestamp);
        assertEq(update.newValue, newValue);
        assertEq(update.referenceId, "reference-123");
        assertEq(update.updateTypeHash, PRICE_HASH);
        assertEq(update.updateId, 1);
        // Market is now always address(0) in stored updates
        assertEq(update.market, address(0));
        assertEq(update.additionalData, additionalData);
    }

    function test_US2_getUpdateById_PreviousValueTracking() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        bytes memory firstPrice = _encodePrice(50);

        vm.startPrank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 50, PRICE_HASH, 100, 1));
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", 75, PRICE_HASH, 200, 2));
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
        oracle.updateLatestRiskRoundData(_createUpdateInput("my-unique-reference-id", 500, PRICE_HASH, 1000, 2));

        ILlamaGuardOracle.RiskParameterUpdate memory update = oracle.getUpdateById(1);
        assertEq(update.referenceId, "my-unique-reference-id");
    }

    function test_US2_RevertWhen_InvalidUpdateId() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_HASH, 1000, 2));

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

    function test_US3_updateLatestRiskRoundData_ValidTypeAccepted() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_HASH, 1000, 2));

        // Verify data was stored via latestRoundData
        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, 500);

        // Also verify via getUpdateById - decode from additionalData for full bundle
        ILlamaGuardOracle.RiskParameterUpdate memory update = oracle.getUpdateById(1);
        (uint256 supply, int256 price, uint256 state) = abi.decode(update.additionalData, (uint256, int256, uint256));
        assertEq(supply, 1000);
        assertEq(state, 2);
        assertEq(price, 500);
    }

    function test_US3_RevertWhen_InvalidUpdateType() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        bytes32 invalidTypeHash = keccak256(bytes("invalid_type"));
        vm.prank(writer);
        vm.expectRevert(abi.encodeWithSelector(ILlamaGuardOracle.UnauthorizedUpdateType.selector, invalidTypeHash));
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, invalidTypeHash, 1000, 2));
    }

    function test_US3_updateLatestRiskRoundData_EmitsParameterUpdatedEvent() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        bytes memory newValue = _encodePrice(500);
        bytes memory emptyPrevValue = "";
        bytes memory additionalData = _encodeAdditionalData(1000, 500, 2);

        vm.prank(writer);
        vm.expectEmit(true, true, true, true);
        emit ParameterUpdated("ref-1", newValue, emptyPrevValue, block.timestamp, PRICE_HASH, 1, additionalData);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_HASH, 1000, 2));
    }

    function test_US3_RevertWhen_UnauthorizedCaller() public {
        vm.prank(nonWriter);
        vm.expectRevert();
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_HASH, 1000, 2));
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
        // Initial round (0) has startedAt = 0, which is the expected initial state
        assertEq(startedAt, 0);
    }

    function testLatestRoundDataAfterUpdate() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        uint256 beforeTs = block.timestamp;
        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 2500, PRICE_HASH, 5000, 7));
        (, int256 answer, uint256 startedAt,,) = oracle.latestRoundData();
        assertEq(answer, 2500);
        assertGe(startedAt, beforeTs);
    }

    function testLatestRoundDataCallableByAnyone() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_HASH, 1000, 2));

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
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_HASH, 1000, 2));
        uint80 newId = oracle.getLatestRoundId();
        assertEq(newId, initialId + 1);
    }

    function testAggregatorStoresMultipleRounds() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        vm.startPrank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 50, PRICE_HASH, 100, 1));
        uint80 r1 = oracle.getLatestRoundId();
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", 75, PRICE_HASH, 200, 2));
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
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_HASH, 1000, 2));
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
            oracle.updateLatestRiskRoundData(
                _createUpdateInput(
                    string(abi.encodePacked("ref-", vm.toString(i))), int256(i * 50), PRICE_HASH, i * 100, i
                )
            );
        }
        vm.stopPrank();

        // Verify via latestRoundData
        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, 500);

        // Verify full data via getUpdateById - decode from additionalData for full bundle
        ILlamaGuardOracle.RiskParameterUpdate memory update = oracle.getUpdateById(10); // 10th update, roundId starts
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
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", _price, PRICE_HASH, _supply, _state));

        // Verify price via latestRoundData
        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, _price);

        // Verify full data via getUpdateById - decode from additionalData for full bundle
        ILlamaGuardOracle.RiskParameterUpdate memory update = oracle.getUpdateById(1);
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
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_HASH, 1000, 2));

        // The index should now point to updateId 1 (first update)
        // Query with any market - the market will be rewritten to the input value
        ILlamaGuardOracle.RiskParameterUpdate memory update =
            oracle.getLatestUpdateByParameterAndMarket(PRICE_HASH, queryMarket);

        assertEq(update.updateId, 1);
        // Market is rewritten to the query parameter
        assertEq(update.market, queryMarket);
        assertEq(update.updateTypeHash, PRICE_HASH);
    }

    function test_UpdateData_OverwritesPreviousIndex() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        address queryMarket = address(0x2222);

        vm.startPrank(writer);
        // First update
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 50, PRICE_HASH, 100, 1));
        uint256 firstUpdateId = oracle.getLatestRoundId();

        // Second update for same type
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", 75, PRICE_HASH, 200, 2));
        uint256 secondUpdateId = oracle.getLatestRoundId();
        vm.stopPrank();

        // Index should point to the latest update
        ILlamaGuardOracle.RiskParameterUpdate memory update =
            oracle.getLatestUpdateByParameterAndMarket(PRICE_HASH, queryMarket);

        assertEq(update.updateId, secondUpdateId);
        assertGt(update.updateId, firstUpdateId);
        assertEq(update.referenceId, "ref-2");
    }

    function test_UpdateData_IndependentIndexPerUpdateType() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        address queryMarket = address(0x3333);

        vm.startPrank(writer);
        // Update for price type
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 50, PRICE_HASH, 100, 1));
        uint256 priceUpdateId = oracle.getLatestRoundId();

        // Update for supply type
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", 75, SUPPLY_HASH, 200, 2));
        uint256 supplyUpdateId = oracle.getLatestRoundId();

        // Update for risk_state type
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-3", 100, RISK_STATE_HASH, 300, 3));
        uint256 riskStateUpdateId = oracle.getLatestRoundId();
        vm.stopPrank();

        // Each updateType should have independent tracking (using bytes32 overload)
        ILlamaGuardOracle.RiskParameterUpdate memory update1 =
            oracle.getLatestUpdateByParameterAndMarket(PRICE_HASH, queryMarket);
        ILlamaGuardOracle.RiskParameterUpdate memory update2 =
            oracle.getLatestUpdateByParameterAndMarket(SUPPLY_HASH, queryMarket);
        ILlamaGuardOracle.RiskParameterUpdate memory update3 =
            oracle.getLatestUpdateByParameterAndMarket(RISK_STATE_HASH, queryMarket);

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
        oracle.updateLatestRiskRoundData(_createUpdateInput("reference-123", 500, PRICE_HASH, 1000, 2));

        ILlamaGuardOracle.RiskParameterUpdate memory update =
            oracle.getLatestUpdateByParameterAndMarket(PRICE_HASH, queryMarket);

        assertEq(update.timestamp, block.timestamp);
        assertEq(update.newValue, newValue);
        assertEq(update.referenceId, "reference-123");
        assertEq(update.updateTypeHash, PRICE_HASH);
        // Market is rewritten to query parameter
        assertEq(update.market, queryMarket);
        assertEq(update.additionalData, additionalData);
    }

    function test_GetLatestUpdateByParameterAndMarket_ReturnsLatestAfterMultipleUpdates() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        address queryMarket = address(0x6666);

        vm.startPrank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 50, PRICE_HASH, 100, 1));
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", 75, PRICE_HASH, 200, 2));
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-3", 100, PRICE_HASH, 300, 3));
        vm.stopPrank();

        ILlamaGuardOracle.RiskParameterUpdate memory update =
            oracle.getLatestUpdateByParameterAndMarket(PRICE_HASH, queryMarket);

        // Should return the latest (third) update
        assertEq(update.referenceId, "ref-3");
        // Decode from additionalData for full bundle
        (uint256 supply,,) = abi.decode(update.additionalData, (uint256, int256, uint256));
        assertEq(supply, 300);
    }

    function test_GetLatestUpdateByParameterAndMarket_RevertsForNonExistentType() public {
        // Query for an updateType that has no updates should revert with InvalidUpdateId(0)
        bytes32 nonExistentHash = keccak256(bytes("nonexistent_type"));
        vm.expectRevert(abi.encodeWithSelector(ILlamaGuardOracle.InvalidUpdateId.selector, 0));
        oracle.getLatestUpdateByParameterAndMarket(nonExistentHash, address(0x9999));
    }

    function test_GetLatestUpdateByParameterAndMarket_RevertsForTypeWithNoUpdates() public {
        // Even valid update types should revert if they have no updates yet
        // PRICE_HASH is valid but has no updates
        vm.expectRevert(abi.encodeWithSelector(ILlamaGuardOracle.InvalidUpdateId.selector, 0));
        oracle.getLatestUpdateByParameterAndMarket(PRICE_HASH, address(0x1));
    }

    function test_GetLatestUpdateByParameterAndMarket_MarketIsRewritten() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("market-ref", 500, PRICE_HASH, 1000, 2));

        // Query with different market addresses - market should be rewritten to query param
        address queryMarket1 = address(0x1111);
        address queryMarket2 = address(0x2222);

        ILlamaGuardOracle.RiskParameterUpdate memory update1 =
            oracle.getLatestUpdateByParameterAndMarket(PRICE_HASH, queryMarket1);
        ILlamaGuardOracle.RiskParameterUpdate memory update2 =
            oracle.getLatestUpdateByParameterAndMarket(PRICE_HASH, queryMarket2);

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

        bytes32 updateTypeHash;
        if (updateTypeIndex == 0) {
            updateTypeHash = PRICE_HASH;
        } else if (updateTypeIndex == 1) {
            updateTypeHash = SUPPLY_HASH;
        } else {
            updateTypeHash = RISK_STATE_HASH;
        }

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("fuzz-ref", price, updateTypeHash, supply, state));

        // Use bytes32 overload for the query
        ILlamaGuardOracle.RiskParameterUpdate memory update =
            oracle.getLatestUpdateByParameterAndMarket(updateTypeHash, queryMarket);

        // Verify correct update is returned with market rewritten to query param
        assertEq(update.market, queryMarket);
        assertEq(update.updateTypeHash, updateTypeHash);
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
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-interface", 500, PRICE_HASH, 1000, 2));

        // Call via interface to verify signature compatibility (using bytes32 overload)
        ILlamaGuardOracle iOracle = ILlamaGuardOracle(address(oracle));
        ILlamaGuardOracle.RiskParameterUpdate memory update =
            iOracle.getLatestUpdateByParameterAndMarket(PRICE_HASH, queryMarket);

        assertEq(update.referenceId, "ref-interface");
        // Market is rewritten to query param
        assertEq(update.market, queryMarket);
    }

    function test_InterfaceConsistency_GetLatestUpdateByParameterAndMarket_StringOverload() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        address queryMarket = address(0x8888);
        string memory updateType = "price";

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-string", 600, PRICE_HASH, 2000, 3));

        // Call via interface using string overload with explicit string memory variable
        ILlamaGuardOracle iOracle = ILlamaGuardOracle(address(oracle));
        ILlamaGuardOracle.RiskParameterUpdate memory update =
            iOracle.getLatestUpdateByParameterAndMarket(updateType, queryMarket);

        assertEq(update.referenceId, "ref-string");
        assertEq(update.market, queryMarket);
        assertEq(update.updateTypeHash, PRICE_HASH);
    }

    function test_Bytes32Overload_MatchesStringOverload() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        address queryMarket = address(0x9999);
        string memory updateType = "price";

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-compare", 700, PRICE_HASH, 3000, 4));

        // Both overloads should return the same data
        ILlamaGuardOracle.RiskParameterUpdate memory updateFromString =
            oracle.getLatestUpdateByParameterAndMarket(updateType, queryMarket);
        ILlamaGuardOracle.RiskParameterUpdate memory updateFromBytes32 =
            oracle.getLatestUpdateByParameterAndMarket(PRICE_HASH, queryMarket);

        assertEq(updateFromString.updateId, updateFromBytes32.updateId);
        assertEq(updateFromString.timestamp, updateFromBytes32.timestamp);
        assertEq(updateFromString.referenceId, updateFromBytes32.referenceId);
        assertEq(updateFromString.updateTypeHash, updateFromBytes32.updateTypeHash);
        assertEq(updateFromString.market, updateFromBytes32.market);
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
    // NOTE: Market authorization is no longer used in updateLatestRiskRoundData, but the management
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

    // T017: test_Constructor_RevertsDuplicateMarkets
    function test_Constructor_RevertsDuplicateMarkets() public {
        // Arrange: Create markets array with duplicates
        address[] memory initialMarkets = new address[](3);
        initialMarkets[0] = market1;
        initialMarkets[1] = market2;
        initialMarkets[2] = market1; // Duplicate

        // Act & Assert: Deploy oracle should revert on duplicate market
        vm.expectRevert(abi.encodeWithSelector(ILlamaGuardOracle.MarketAlreadyAuthorized.selector, market1));
        new LlamaGuardOracle(8, "Test", 1, defaultUpdateTypes, initialMarkets);
    }
}
