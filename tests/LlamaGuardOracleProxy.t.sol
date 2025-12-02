// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { LlamaGuardOracle } from "../src/LlamaGuardOracle.sol";
import { LlamaGuardOracleProxy } from "../src/LlamaGuardOracleProxy.sol";
import { ILlamaGuardOracle } from "../src/interfaces/ILlamaGuardOracle.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract LlamaGuardOracleProxyTest is Test {
    LlamaGuardOracle internal oracle;
    LlamaGuardOracleProxy internal proxy;

    address internal owner = address(this);
    address internal expectedAuthor = address(0xA11CE);
    address internal expectedForwarder;
    bytes10 internal expectedWorkflowName = bytes10("WORKFLOW1");
    bytes32 internal expectedWorkflowId = bytes32("WORKFLOWCID_ABCDEFGHIJKLMNOPQRST");
    string internal proxyDescription = "Proxy: Mock Feed";

    // Default test market for legacy tests
    address internal defaultMarket = address(0xDEFA);

    string[] internal defaultUpdateTypes;

    function setUp() public {
        expectedForwarder = address(this); // in tests, we call onReport directly

        // Setup default update types
        defaultUpdateTypes = new string[](3);
        defaultUpdateTypes[0] = "price";
        defaultUpdateTypes[1] = "supply";
        defaultUpdateTypes[2] = "risk_state";

        address[] memory initialMarkets = new address[](1);
        initialMarkets[0] = defaultMarket;
        oracle = new LlamaGuardOracle(8, "Mock Feed", 1, defaultUpdateTypes, initialMarkets);
        proxy = new LlamaGuardOracleProxy(
            address(oracle),
            expectedAuthor,
            expectedForwarder,
            expectedWorkflowName,
            expectedWorkflowId,
            proxyDescription
        );

        // Grant writer role to proxy so it can forward updates
        oracle.grantRole(oracle.WRITER_ROLE(), address(proxy));
    }

    /// @dev Encode report for proxy - newValue is just price, additionalData is full bundle
    function _encodeProxyReport(
        string memory referenceId,
        uint256 supply_,
        int256 price_,
        uint256 state_,
        string memory updateType
    )
        internal
        pure
        returns (bytes memory)
    {
        bytes memory newValue = abi.encode(price_);
        bytes memory additionalData = abi.encode(supply_, price_, state_);
        return abi.encode(referenceId, newValue, updateType, additionalData);
    }

    function testProxyForwardsUpdates() public {
        // Build metadata matching expected values so onReport passes in base template
        bytes memory metadata = _buildMetadata(expectedWorkflowId, expectedAuthor, expectedWorkflowName);

        bytes memory report = _encodeProxyReport("ref-1", 1000, 321, 9, "price");

        proxy.onReport(metadata, report);

        // Verify via latestRoundData
        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, 321);

        // Verify full data via getUpdateById - decode from additionalData for full bundle
        ILlamaGuardOracle.RiskParameterUpdate memory update = oracle.getUpdateById(2);
        (uint256 supply, int256 price, uint256 state) = abi.decode(update.additionalData, (uint256, int256, uint256));
        assertEq(supply, 1000);
        assertEq(state, 9);
        assertEq(price, 321);
    }

    function testOnReportRevertsForWrongAuthor() public {
        bytes memory metadata = _buildMetadata(expectedWorkflowId, address(0xBEEF), expectedWorkflowName);
        bytes memory report = _encodeProxyReport("ref-1", 100, 200, 3, "price");

        vm.expectRevert();
        proxy.onReport(metadata, report);
    }

    function testOnReportRevertsForWrongWorkflow() public {
        bytes memory metadata = _buildMetadata(expectedWorkflowId, expectedAuthor, bytes10("WRONGNAME"));
        bytes memory report = _encodeProxyReport("ref-1", 500, 600, 7, "price");

        vm.expectRevert();
        proxy.onReport(metadata, report);
    }

    function testSetLlamaGuardOracleRequiresWriteAccess() public {
        // New oracle without granting role to proxy should revert
        address[] memory noMarkets = new address[](0);
        LlamaGuardOracle newOracle = new LlamaGuardOracle(8, "New Feed", 1, defaultUpdateTypes, noMarkets);

        vm.expectRevert(LlamaGuardOracleProxy.InvalidLlamaGuardOracle.selector);
        proxy.setLlamaGuardOracle(address(newOracle));

        // Grant write role and try again
        newOracle.grantRole(newOracle.WRITER_ROLE(), address(proxy));
        proxy.setLlamaGuardOracle(address(newOracle));

        assertEq(address(proxy.llamaguardOracle()), address(newOracle));
    }

    function test_RevertWhen_ConstructorCalledWithZeroAddress() public {
        vm.expectRevert(LlamaGuardOracleProxy.InvalidLlamaGuardOracle.selector);
        new LlamaGuardOracleProxy(
            address(0), expectedAuthor, expectedForwarder, expectedWorkflowName, expectedWorkflowId, proxyDescription
        );
    }

    function test_SetIsReportWriteSecured_EnablesWriteSecurity() public {
        // Disable security first
        proxy.setIsReportWriteSecured(false);
        assertFalse(proxy.isReportWriteSecured(), "Security should be disabled");

        // Re-enable security
        proxy.setIsReportWriteSecured(true);
        assertTrue(proxy.isReportWriteSecured(), "Security should be enabled");
    }

    function test_SetIsReportWriteSecured_DisablesWriteSecurity() public {
        // Security is enabled by default
        assertTrue(proxy.isReportWriteSecured(), "Security should be enabled by default");

        // Disable security
        proxy.setIsReportWriteSecured(false);
        assertFalse(proxy.isReportWriteSecured(), "Security should be disabled");
    }

    function test_RevertWhen_SetIsReportWriteSecuredCalledByNonOwner() public {
        address nonOwner = address(0xBEEF);

        vm.prank(nonOwner);
        vm.expectRevert();
        proxy.setIsReportWriteSecured(false);
    }

    function test_OnReport_BypassesValidationWhenSecurityDisabled() public {
        // Disable security
        proxy.setIsReportWriteSecured(false);

        // Build metadata with wrong values - should not revert
        bytes memory wrongMetadata = _buildMetadata(bytes32("WRONG_ID"), address(0xDEAD), bytes10("WRONG"));
        bytes memory report = _encodeProxyReport("ref-1", 5000, 999, 7, "price");

        // Should succeed even with wrong metadata
        proxy.onReport(wrongMetadata, report);

        // Verify the update was processed via latestRoundData
        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, 999, "Price should be updated");

        // Verify full data via getUpdateById - decode from additionalData for full bundle
        ILlamaGuardOracle.RiskParameterUpdate memory update = oracle.getUpdateById(2);
        (uint256 supply, int256 price, uint256 state) = abi.decode(update.additionalData, (uint256, int256, uint256));
        assertEq(supply, 5000, "Supply should be updated");
        assertEq(state, 7, "State should be updated");
        assertEq(price, 999, "Price should be updated");
    }

    function test_Description_IsSetCorrectly() public view {
        assertEq(proxy.description(), proxyDescription, "Description should match constructor parameter");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SETTER FUNCTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_SetExpectedAuthor_UpdatesValue() public {
        address newAuthor = address(0xAABB11);
        proxy.setExpectedAuthor(newAuthor);
        assertEq(proxy.EXPECTED_AUTHOR(), newAuthor, "Expected author should be updated");
    }

    function test_RevertWhen_SetExpectedAuthor_CalledByNonOwner() public {
        address nonOwner = address(0xBEEF);
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        proxy.setExpectedAuthor(address(0x1234));
    }

    function test_SetExpectedForwarder_UpdatesValue() public {
        address newForwarder = address(0xCCDD22);
        proxy.setExpectedForwarder(newForwarder);
        assertEq(proxy.EXPECTED_FORWARDER(), newForwarder, "Expected forwarder should be updated");
    }

    function test_RevertWhen_SetExpectedForwarder_CalledByNonOwner() public {
        address nonOwner = address(0xBEEF);
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        proxy.setExpectedForwarder(address(0x1234));
    }

    function test_SetExpectedWorkflowName_UpdatesValue() public {
        bytes10 newName = bytes10("NEWNAME123");
        proxy.setExpectedWorkflowName(newName);
        assertEq(proxy.EXPECTED_WORKFLOW_NAME(), newName, "Expected workflow name should be updated");
    }

    function test_RevertWhen_SetExpectedWorkflowName_CalledByNonOwner() public {
        address nonOwner = address(0xBEEF);
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        proxy.setExpectedWorkflowName(bytes10("NEWNAME"));
    }

    function test_SetExpectedWorkflowId_UpdatesValue() public {
        bytes32 newId = bytes32("NEW_WORKFLOW_ID_VALUE__________");
        proxy.setExpectedWorkflowId(newId);
        assertEq(proxy.EXPECTED_WORKFLOW_ID(), newId, "Expected workflow ID should be updated");
    }

    function test_RevertWhen_SetExpectedWorkflowId_CalledByNonOwner() public {
        address nonOwner = address(0xBEEF);
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        proxy.setExpectedWorkflowId(bytes32("NEWID"));
    }

    function test_SetExpectedValues_UpdatesAllValues() public {
        address newAuthor = address(0x1111);
        address newForwarder = address(0x2222);
        bytes10 newName = bytes10("NEWWORKFLO");
        bytes32 newId = bytes32("NEW_WORKFLOW_CID_______________");

        proxy.setExpectedValues(newAuthor, newForwarder, newName, newId);

        assertEq(proxy.EXPECTED_AUTHOR(), newAuthor, "Expected author should be updated");
        assertEq(proxy.EXPECTED_FORWARDER(), newForwarder, "Expected forwarder should be updated");
        assertEq(proxy.EXPECTED_WORKFLOW_NAME(), newName, "Expected workflow name should be updated");
        assertEq(proxy.EXPECTED_WORKFLOW_ID(), newId, "Expected workflow ID should be updated");
    }

    function test_RevertWhen_SetExpectedValues_CalledByNonOwner() public {
        address nonOwner = address(0xBEEF);
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        proxy.setExpectedValues(address(0x1), address(0x2), bytes10("NAME"), bytes32("ID"));
    }

    function test_SetExpectedValues_VerifiesOnReport() public {
        // Set new expected values
        address newAuthor = address(0xAA11);
        address newForwarder = address(this);
        bytes10 newName = bytes10("NEWNAME");
        bytes32 newId = bytes32("NEW_WORKFLOW_CID_0123456789_____");

        proxy.setExpectedValues(newAuthor, newForwarder, newName, newId);

        // Build metadata with new expected values
        bytes memory metadata = _buildMetadata(newId, newAuthor, newName);
        bytes memory report = _encodeProxyReport("ref-new", 3000, 400, 5, "price");

        // Should succeed with new expected values
        proxy.onReport(metadata, report);

        // Verify update was processed
        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, 400, "Price should be updated");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // OWNABLE2STEP TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_TransferOwnership_SetsPendingOwner() public {
        address newOwner = address(0xEEFF33);

        proxy.transferOwnership(newOwner);

        // Owner should still be the original owner
        assertEq(proxy.owner(), owner, "Owner should not change immediately");
        // Pending owner should be set
        assertEq(proxy.pendingOwner(), newOwner, "Pending owner should be set");
    }

    function test_AcceptOwnership_TransfersOwnership() public {
        address newOwner = address(0xEEFF33);

        // Step 1: Transfer ownership (sets pending owner)
        proxy.transferOwnership(newOwner);

        // Step 2: Accept ownership as new owner
        vm.prank(newOwner);
        proxy.acceptOwnership();

        // Verify ownership transferred
        assertEq(proxy.owner(), newOwner, "Owner should be new owner");
        assertEq(proxy.pendingOwner(), address(0), "Pending owner should be cleared");
    }

    function test_RevertWhen_AcceptOwnership_CalledByNonPendingOwner() public {
        address newOwner = address(0xEEFF33);
        address randomAddress = address(0xFF0011);

        proxy.transferOwnership(newOwner);

        // Try to accept as random address (not pending owner)
        vm.prank(randomAddress);
        vm.expectRevert();
        proxy.acceptOwnership();
    }

    function test_TransferOwnership_ThenAccept_AllowsNewOwnerToCallOnlyOwner() public {
        address newOwner = address(0xEEFF33);

        // Transfer and accept ownership
        proxy.transferOwnership(newOwner);
        vm.prank(newOwner);
        proxy.acceptOwnership();

        // New owner should be able to call onlyOwner functions
        vm.prank(newOwner);
        proxy.setExpectedAuthor(address(0xABCD));
        assertEq(proxy.EXPECTED_AUTHOR(), address(0xABCD), "New owner should be able to set expected author");
    }

    function test_TransferOwnership_OldOwnerCannotCallOnlyOwner() public {
        address newOwner = address(0xEEFF33);

        // Transfer and accept ownership
        proxy.transferOwnership(newOwner);
        vm.prank(newOwner);
        proxy.acceptOwnership();

        // Old owner should NOT be able to call onlyOwner functions
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        proxy.setExpectedAuthor(address(0xFA11));
    }

    function _buildMetadata(
        bytes32 workflowId,
        address workflowOwner,
        bytes10 workflowName
    )
        internal
        pure
        returns (bytes memory)
    {
        bytes memory workflowCid = abi.encode(workflowId);
        bytes memory reportName = new bytes(2);
        return abi.encodePacked(workflowCid, workflowName, bytes20(workflowOwner), reportName);
    }
}
