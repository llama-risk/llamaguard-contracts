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
        oracle.addUpdateType("new_custom_type");

        assertTrue(oracle.isValidUpdateType("new_custom_type"));

        // Verify new type is at index 4 via public array access (after price, supply, risk_state, boundedNAV)
        assertEq(oracle.updateTypes(4), "new_custom_type");
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
        assertEq(oracle.updateTypes(0), PRICE_TYPE);
        assertEq(oracle.updateTypes(1), SUPPLY_TYPE);
        assertEq(oracle.updateTypes(2), RISK_STATE_TYPE);
        assertEq(oracle.updateTypes(3), BOUNDED_NAV_TYPE);

        // Add a new type and verify it's appended
        oracle.addUpdateType("new_type");
        assertEq(oracle.updateTypes(4), "new_type");
        assertTrue(oracle.isValidUpdateType("new_type"));
    }

    function test_US4_RevertWhen_NonOwnerAddsType() public {
        vm.prank(nonWriter);
        vm.expectRevert();
        oracle.addUpdateType("new_type");
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
}
