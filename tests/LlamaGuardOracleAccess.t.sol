// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { LlamaGuardOracleTestBase } from "./LlamaGuardOracleTestBase.sol";
import { LlamaGuardOracle } from "../src/LlamaGuardOracle.sol";
import { ILlamaGuardOracle } from "../src/interfaces/ILlamaGuardOracle.sol";

/// @title LlamaGuardOracleAccessTest
/// @notice Access control and update type management tests for LlamaGuardOracle
contract LlamaGuardOracleAccessTest is LlamaGuardOracleTestBase {
    // ═══════════════════════════════════════════════════════════════════════════
    // USER STORY 3: AUTHORIZED DATA UPDATES WITH TYPE VALIDATION
    // ═══════════════════════════════════════════════════════════════════════════

    function test_US3_updateLatestRiskRoundData_ValidTypeAccepted() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_TYPE, 1000, 2));

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

        string memory invalidType = "invalid_type";
        vm.prank(writer);
        vm.expectRevert(abi.encodeWithSelector(ILlamaGuardOracle.UnauthorizedUpdateType.selector, invalidType));
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, invalidType, 1000, 2));
    }

    function test_US3_updateLatestRiskRoundData_EmitsParameterUpdatedEvent() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        bytes memory newValue = _encodePrice(500);
        bytes memory emptyPrevValue = "";
        bytes memory additionalData = _encodeAdditionalData(1000, 500, 2);

        vm.prank(writer);
        vm.expectEmit(true, true, true, true);
        emit ParameterUpdated("ref-1", newValue, emptyPrevValue, block.timestamp, PRICE_TYPE, 1, additionalData);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_TYPE, 1000, 2));
    }

    function test_US3_RevertWhen_UnauthorizedCaller() public {
        vm.prank(nonWriter);
        vm.expectRevert();
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_TYPE, 1000, 2));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // USER STORY 4: UPDATE TYPE MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    function test_US4_addUpdateType_OwnerSuccess() public {
        oracle.addUpdateType("new_custom_type", type(uint256).max);

        assertTrue(oracle.isValidUpdateType("new_custom_type"));

        // Verify new type is at index 4 via public array access (after price, supply, risk_state, boundedNAV)
        assertEq(oracle.updateTypes(4), "new_custom_type");
    }

    function test_US4_addUpdateType_EmitsUpdateTypeAddedEvent() public {
        vm.expectEmit(true, false, false, true);
        emit UpdateTypeAdded("new_type", type(uint256).max);
        oracle.addUpdateType("new_type", type(uint256).max);
    }

    function test_US4_RevertWhen_DuplicateUpdateType() public {
        vm.expectRevert(abi.encodeWithSelector(ILlamaGuardOracle.UpdateTypeAlreadyExists.selector, "price"));
        oracle.addUpdateType("price", type(uint256).max);
    }

    function test_US4_RevertWhen_InvalidUpdateTypeString() public {
        // Empty string
        vm.expectRevert(abi.encodeWithSelector(ILlamaGuardOracle.InvalidUpdateTypeString.selector, ""));
        oracle.addUpdateType("", type(uint256).max);

        // Too long string (> 64 chars)
        string memory longString = "this_is_a_very_long_string_that_exceeds_the_64_character_limit_for_update_types";
        vm.expectRevert(abi.encodeWithSelector(ILlamaGuardOracle.InvalidUpdateTypeString.selector, longString));
        oracle.addUpdateType(longString, type(uint256).max);
    }

    function test_US4_updateTypesArrayAccess_ReturnsAllTypes() public {
        // Verify initial types via public array access
        assertEq(oracle.updateTypes(0), PRICE_TYPE);
        assertEq(oracle.updateTypes(1), SUPPLY_TYPE);
        assertEq(oracle.updateTypes(2), RISK_STATE_TYPE);
        assertEq(oracle.updateTypes(3), BOUNDED_NAV_TYPE);

        // Add a new type and verify it's appended
        oracle.addUpdateType("new_type", type(uint256).max);
        assertEq(oracle.updateTypes(4), "new_type");
        assertTrue(oracle.isValidUpdateType("new_type"));
    }

    function test_US4_RevertWhen_NonOwnerAddsType() public {
        vm.prank(nonWriter);
        vm.expectRevert();
        oracle.addUpdateType("new_type", type(uint256).max);
    }

    function test_US4_isValidUpdateType() public view {
        assertTrue(oracle.isValidUpdateType(PRICE_TYPE));
        assertTrue(oracle.isValidUpdateType(SUPPLY_TYPE));
        assertTrue(oracle.isValidUpdateType(RISK_STATE_TYPE));
        assertTrue(oracle.isValidUpdateType(BOUNDED_NAV_TYPE));
        assertFalse(oracle.isValidUpdateType("invalid"));
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

    function test_GetLatestUpdateByParameterAndMarket_RevertsForUnauthorizedMarket() public {
        // Grant writer role and make an update
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_TYPE, 1000, 2));

        // Try to get update for unauthorized market
        address unauthorizedMarket_ = address(0x9999);
        vm.expectRevert(abi.encodeWithSelector(ILlamaGuardOracle.UnauthorizedMarket.selector, unauthorizedMarket_));
        oracle.getLatestUpdateByParameterAndMarket(PRICE_TYPE, unauthorizedMarket_);
    }

    function test_GetLatestUpdateByParameterAndMarket_SucceedsForAuthorizedMarket() public {
        // Grant writer role and make an update
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_TYPE, 1000, 2));

        // Get update for authorized market (defaultMarket from setUp)
        ILlamaGuardOracle.RiskParameterUpdate memory update =
            oracle.getLatestUpdateByParameterAndMarket(PRICE_TYPE, defaultMarket);

        assertEq(update.market, defaultMarket);
        int256 price = abi.decode(update.newValue, (int256));
        assertEq(price, 500);
    }

    function test_RemoveUpdateType_Success() public {
        // Verify price type exists
        assertTrue(oracle.isValidUpdateType(PRICE_TYPE));

        // Remove the update type
        oracle.removeUpdateType(PRICE_TYPE);

        // Verify it's removed
        assertFalse(oracle.isValidUpdateType(PRICE_TYPE));
    }

    function test_RemoveUpdateType_EmitsUpdateTypeRemovedEvent() public {
        vm.expectEmit(true, false, false, true);
        emit ILlamaGuardOracle.UpdateTypeRemoved(PRICE_TYPE);
        oracle.removeUpdateType(PRICE_TYPE);
    }

    function test_RemoveUpdateType_RevertsForNonExistentType() public {
        string memory nonExistentType = "nonexistent";
        vm.expectRevert(abi.encodeWithSelector(ILlamaGuardOracle.UpdateTypeNotFound.selector, nonExistentType));
        oracle.removeUpdateType(nonExistentType);
    }

    function test_RemoveUpdateType_RevertsForNonAdmin() public {
        vm.prank(nonWriter);
        vm.expectRevert();
        oracle.removeUpdateType(PRICE_TYPE);
    }

    function test_RemoveUpdateType_UpdatesArrayCorrectly() public {
        // Initial state: 4 types [price, supply, risk_state, boundedNAV]
        assertEq(oracle.updateTypes(0), PRICE_TYPE);
        assertEq(oracle.updateTypes(1), SUPPLY_TYPE);
        assertEq(oracle.updateTypes(2), RISK_STATE_TYPE);
        assertEq(oracle.updateTypes(3), BOUNDED_NAV_TYPE);

        // Remove price type (index 0) - should swap with last element
        oracle.removeUpdateType(PRICE_TYPE);

        // Now should have 3 types: [boundedNAV, supply, risk_state]
        assertEq(oracle.updateTypes(0), BOUNDED_NAV_TYPE);
        assertEq(oracle.updateTypes(1), SUPPLY_TYPE);
        assertEq(oracle.updateTypes(2), RISK_STATE_TYPE);

        // Trying to access index 3 should revert
        vm.expectRevert();
        oracle.updateTypes(3);
    }

    function test_RemoveUpdateType_BlocksSubsequentUpdates() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        // Remove price type
        oracle.removeUpdateType(PRICE_TYPE);

        // Try to make an update with removed type - should revert
        vm.prank(writer);
        vm.expectRevert(abi.encodeWithSelector(ILlamaGuardOracle.UnauthorizedUpdateType.selector, PRICE_TYPE));
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_TYPE, 1000, 2));
    }

    function test_SetMaxPriceDeviation_Success() public {
        // Set max deviation to 5% (500 basis points)
        oracle.setMaxPriceDeviation(500);
        assertEq(oracle.maxPriceDeviation(), 500);
    }

    function test_SetMaxPriceDeviation_EmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit ILlamaGuardOracle.MaxPriceDeviationUpdated(0, 500);
        oracle.setMaxPriceDeviation(500);
    }

    function test_SetMaxPriceDeviation_RevertsForNonAdmin() public {
        vm.prank(nonWriter);
        vm.expectRevert();
        oracle.setMaxPriceDeviation(500);
    }

    function test_SetMaxPriceDeviation_CanBeDisabled() public {
        // First set it
        oracle.setMaxPriceDeviation(500);
        assertEq(oracle.maxPriceDeviation(), 500);

        // Then disable
        oracle.setMaxPriceDeviation(0);
        assertEq(oracle.maxPriceDeviation(), 0);
    }

    function test_PriceDeviationCheck_AllowsUpdateWithinLimit() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        // Set max deviation to 10% (1000 basis points)
        oracle.setMaxPriceDeviation(1000);

        // First update
        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 1000, PRICE_TYPE, 1000, 2));

        // Second update with 5% increase (within limit)
        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", 1050, PRICE_TYPE, 1000, 2));

        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, 1050);
    }

    function test_PriceDeviationCheck_RevertsWhenExceedsLimit() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        // Set max deviation to 5% (500 basis points)
        oracle.setMaxPriceDeviation(500);

        // First update
        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 1000, PRICE_TYPE, 1000, 2));

        // Second update with 10% increase (exceeds limit)
        vm.prank(writer);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILlamaGuardOracle.PriceDeviationExceeded.selector,
                1000, // previousPrice
                1100, // newPrice
                1000, // deviation (10% = 1000 bps)
                500 // maxAllowed
            )
        );
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", 1100, PRICE_TYPE, 1000, 2));
    }

    function test_PriceDeviationCheck_SkippedWhenDisabled() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        // Max deviation is 0 (disabled by default)
        assertEq(oracle.maxPriceDeviation(), 0);

        // First update
        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 1000, PRICE_TYPE, 1000, 2));

        // Second update with 100% increase (would fail if check was enabled)
        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", 2000, PRICE_TYPE, 1000, 2));

        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, 2000);
    }

    function test_PriceDeviationCheck_SkippedForFirstUpdate() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        // Set max deviation to 5% (500 basis points)
        oracle.setMaxPriceDeviation(500);

        // First update should succeed even with large price (no previous price to compare)
        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 1_000_000, PRICE_TYPE, 1000, 2));

        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, 1_000_000);
    }

    function test_PriceDeviationCheck_SkippedWhenPreviousPriceIsZero() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        // Set max deviation to 5% (500 basis points)
        oracle.setMaxPriceDeviation(500);

        // First update with zero price
        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 0, PRICE_TYPE, 1000, 2));

        // Second update should succeed (previous price was 0)
        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", 1000, PRICE_TYPE, 1000, 2));

        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, 1000);
    }

    function test_PriceDeviationCheck_WorksWithNegativePrices() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        // Set max deviation to 10% (1000 basis points)
        oracle.setMaxPriceDeviation(1000);

        // First update with negative price
        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", -1000, PRICE_TYPE, 1000, 2));

        // Second update with 5% move (within limit)
        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", -1050, PRICE_TYPE, 1000, 2));

        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, -1050);
    }

    function test_PriceDeviationCheck_RevertsWithNegativePricesExceedingLimit() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        // Set max deviation to 5% (500 basis points)
        oracle.setMaxPriceDeviation(500);

        // First update with negative price
        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", -1000, PRICE_TYPE, 1000, 2));

        // Second update with 10% move (exceeds limit)
        vm.prank(writer);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILlamaGuardOracle.PriceDeviationExceeded.selector,
                -1000, // previousPrice
                -1100, // newPrice
                1000, // deviation (10% = 1000 bps)
                500 // maxAllowed
            )
        );
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", -1100, PRICE_TYPE, 1000, 2));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADDITIONAL DATA LENGTH VALIDATION TESTS (HAL-05)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_AdditionalDataLength_ValidLengthAccepted() public {
        // additionalData for _createUpdateInput is abi.encode(uint256, int256, uint256) = 96 bytes
        uint256 expectedLength = 96;

        // Add a type with specific expected length
        oracle.addUpdateType("validated_type", expectedLength);
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, "validated_type", 1000, 2));

        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, 500);
    }

    function test_AdditionalDataLength_RevertWhen_TooShort() public {
        uint256 expectedLength = 96;
        oracle.addUpdateType("validated_type", expectedLength);
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        // Create input with shorter additionalData (32 bytes instead of 96)
        ILlamaGuardOracle.UpdateInput memory input = ILlamaGuardOracle.UpdateInput({
            referenceId: "ref-1",
            newValue: abi.encode(int256(500)),
            updateType: "validated_type",
            additionalData: abi.encode(uint256(1000)) // only 32 bytes
        });

        vm.prank(writer);
        vm.expectRevert(abi.encodeWithSelector(ILlamaGuardOracle.InvalidAdditionalDataLength.selector, 32, 96));
        oracle.updateLatestRiskRoundData(input);
    }

    function test_AdditionalDataLength_RevertWhen_TooLong() public {
        uint256 expectedLength = 96;
        oracle.addUpdateType("validated_type", expectedLength);
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        // Create input with longer additionalData (128 bytes instead of 96)
        ILlamaGuardOracle.UpdateInput memory input = ILlamaGuardOracle.UpdateInput({
            referenceId: "ref-1",
            newValue: abi.encode(int256(500)),
            updateType: "validated_type",
            additionalData: abi.encode(uint256(1), uint256(2), uint256(3), uint256(4)) // 128 bytes
        });

        vm.prank(writer);
        vm.expectRevert(abi.encodeWithSelector(ILlamaGuardOracle.InvalidAdditionalDataLength.selector, 128, 96));
        oracle.updateLatestRiskRoundData(input);
    }

    function test_AdditionalDataLength_SentinelSkipsValidation() public {
        // Default types use sentinel (type(uint256).max) - any length should work
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        // Use default PRICE_TYPE which has sentinel value
        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_TYPE, 1000, 2));

        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, 500);
    }

    function test_AdditionalDataLength_ZeroMeansEmpty() public {
        // expectedLength = 0 means additionalData must be empty
        oracle.addUpdateType("empty_data_type", 0);
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        // Create input with empty additionalData
        ILlamaGuardOracle.UpdateInput memory input = ILlamaGuardOracle.UpdateInput({
            referenceId: "ref-1",
            newValue: abi.encode(int256(500)),
            updateType: "empty_data_type",
            additionalData: "" // empty
        });

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(input);

        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, 500);
    }

    function test_AdditionalDataLength_RevertWhen_NonEmptyButZeroExpected() public {
        oracle.addUpdateType("empty_data_type", 0);
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        vm.expectRevert(abi.encodeWithSelector(ILlamaGuardOracle.InvalidAdditionalDataLength.selector, 96, 0));
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, "empty_data_type", 1000, 2));
    }

    function test_SetExpectedAdditionalDataLength_Success() public {
        // Set length on existing type
        oracle.setExpectedAdditionalDataLength(PRICE_TYPE, 96);
        assertEq(oracle.getExpectedAdditionalDataLength(PRICE_TYPE), 96);
    }

    function test_SetExpectedAdditionalDataLength_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit ILlamaGuardOracle.ExpectedAdditionalDataLengthUpdated(PRICE_TYPE, 96);
        oracle.setExpectedAdditionalDataLength(PRICE_TYPE, 96);
    }

    function test_SetExpectedAdditionalDataLength_RevertWhen_NonExistentType() public {
        string memory nonExistent = "nonexistent";
        vm.expectRevert(abi.encodeWithSelector(ILlamaGuardOracle.UpdateTypeNotFound.selector, nonExistent));
        oracle.setExpectedAdditionalDataLength(nonExistent, 96);
    }

    function test_SetExpectedAdditionalDataLength_RevertWhen_NonAdmin() public {
        vm.prank(nonWriter);
        vm.expectRevert();
        oracle.setExpectedAdditionalDataLength(PRICE_TYPE, 96);
    }

    function test_SetExpectedAdditionalDataLength_CanDisableValidation() public {
        // First set a length
        oracle.setExpectedAdditionalDataLength(PRICE_TYPE, 96);
        assertEq(oracle.getExpectedAdditionalDataLength(PRICE_TYPE), 96);

        // Disable by setting back to sentinel
        oracle.setExpectedAdditionalDataLength(PRICE_TYPE, type(uint256).max);
        assertEq(oracle.getExpectedAdditionalDataLength(PRICE_TYPE), type(uint256).max);
    }

    function test_GetExpectedAdditionalDataLength_ReturnsDefaultSentinel() public view {
        // Default types initialized with sentinel
        assertEq(oracle.getExpectedAdditionalDataLength(PRICE_TYPE), type(uint256).max);
    }

    function test_AddUpdateType_WithExpectedLength_StoresCorrectly() public {
        oracle.addUpdateType("typed_update", 64);
        assertEq(oracle.getExpectedAdditionalDataLength("typed_update"), 64);
        assertTrue(oracle.isValidUpdateType("typed_update"));
    }

    function test_PriceDeviationCheck_BoundaryCondition() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        // Set max deviation to exactly 10% (1000 basis points)
        oracle.setMaxPriceDeviation(1000);

        // First update
        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 1000, PRICE_TYPE, 1000, 2));

        // Update with exactly 10% deviation (should pass since deviation <= max)
        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", 1100, PRICE_TYPE, 1000, 2));

        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, 1100);
    }

    function test_PriceDeviationCheck_AllowsDecreaseWithinLimit() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        oracle.setMaxPriceDeviation(1000); // 10%

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 1000, PRICE_TYPE, 1000, 2));

        // 5% decrease (within limit)
        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", 950, PRICE_TYPE, 1000, 2));

        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, 950);
    }

    function test_PriceDeviationCheck_RevertsWhenDecreaseExceedsLimit() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        oracle.setMaxPriceDeviation(500); // 5%

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 1000, PRICE_TYPE, 1000, 2));

        // 15% decrease (exceeds limit)
        vm.prank(writer);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILlamaGuardOracle.PriceDeviationExceeded.selector,
                1000, // previousPrice
                850, // newPrice
                1500, // deviation (15% = 1500 bps)
                500 // maxAllowed
            )
        );
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", 850, PRICE_TYPE, 1000, 2));
    }

    function test_PriceDeviationCheck_CrossingZeroPositiveToNegative() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        oracle.setMaxPriceDeviation(500); // 5%

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 100, PRICE_TYPE, 1000, 2));

        // Crossing zero: 100 -> -50 is 150% deviation
        vm.prank(writer);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILlamaGuardOracle.PriceDeviationExceeded.selector,
                100, // previousPrice
                -50, // newPrice
                15_000, // deviation (150% = 15000 bps)
                500 // maxAllowed
            )
        );
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", -50, PRICE_TYPE, 1000, 2));
    }

    function test_PriceDeviationCheck_CrossingZeroNegativeToPositive() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        oracle.setMaxPriceDeviation(500); // 5%

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", -100, PRICE_TYPE, 1000, 2));

        // Crossing zero: -100 -> 50 is 150% deviation
        vm.prank(writer);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILlamaGuardOracle.PriceDeviationExceeded.selector,
                -100, // previousPrice
                50, // newPrice
                15_000, // deviation (150% = 15000 bps)
                500 // maxAllowed
            )
        );
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", 50, PRICE_TYPE, 1000, 2));
    }

    function test_PriceDeviationCheck_AllowsNegativeToLessNegativeWithinLimit() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        oracle.setMaxPriceDeviation(1000); // 10%

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", -1000, PRICE_TYPE, 1000, 2));

        // 5% move towards zero (within limit): -1000 -> -950
        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", -950, PRICE_TYPE, 1000, 2));

        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, -950);
    }

    function test_PriceDeviationCheck_RevertsWhenNegativeToLessNegativeExceedsLimit() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        oracle.setMaxPriceDeviation(500); // 5%

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", -1000, PRICE_TYPE, 1000, 2));

        // 20% move towards zero (exceeds limit): -1000 -> -800
        vm.prank(writer);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILlamaGuardOracle.PriceDeviationExceeded.selector,
                -1000, // previousPrice
                -800, // newPrice
                2000, // deviation (20% = 2000 bps)
                500 // maxAllowed
            )
        );
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", -800, PRICE_TYPE, 1000, 2));
    }

    function test_PriceDeviationCheck_AllowsNegativeToMoreNegativeWithinLimit() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        oracle.setMaxPriceDeviation(1000); // 10%

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", -100, PRICE_TYPE, 1000, 2));

        // 5% move away from zero (within limit): -100 -> -105
        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", -105, PRICE_TYPE, 1000, 2));

        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, -105);
    }

    function test_PriceDeviationCheck_RevertsWhenNegativeToMoreNegativeExceedsLimit() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        oracle.setMaxPriceDeviation(500); // 5%

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", -100, PRICE_TYPE, 1000, 2));

        // 100% move away from zero (exceeds limit): -100 -> -200
        vm.prank(writer);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILlamaGuardOracle.PriceDeviationExceeded.selector,
                -100, // previousPrice
                -200, // newPrice
                10_000, // deviation (100% = 10000 bps)
                500 // maxAllowed
            )
        );
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", -200, PRICE_TYPE, 1000, 2));
    }
}
