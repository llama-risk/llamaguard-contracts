// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { LlamaGuardOracle } from "../src/LlamaGuardOracle.sol";
import { LlamaGuardOracleProxy } from "../src/LlamaGuardOracleProxy.sol";
import { AbstractCreReceiver } from "../src/abstracts/AbstractCreReceiver.sol";
import { ILlamaGuardOracle } from "../src/interfaces/ILlamaGuardOracle.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract LlamaGuardOracleProxyTest is Test {
    LlamaGuardOracle internal oracle;
    LlamaGuardOracleProxy internal proxy;

    address internal owner = makeAddr("owner");
    address internal expectedAuthor = makeAddr("expectedAuthor");
    address internal expectedForwarder;
    bytes10 internal expectedWorkflowName = bytes10("WORKFLOW1");
    bytes32 internal expectedWorkflowId = bytes32("WORKFLOWCID_ABCDEFGHIJKLMNOPQRST");
    string internal proxyDescription = "Proxy: Mock Feed";

    address internal defaultMarket = makeAddr("defaultMarket");

    string[] internal defaultUpdateTypes;

    // Pre-computed hash for price update type
    bytes32 internal constant PRICE_HASH = keccak256(bytes("price"));

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

        // Deploy proxy as owner so that owner variable matches actual ownership
        vm.prank(owner);
        proxy = new LlamaGuardOracleProxy(
            address(oracle),
            expectedWorkflowId,
            expectedForwarder,
            expectedAuthor,
            expectedWorkflowName,
            proxyDescription
        );

        // Grant writer role to proxy so it can forward updates
        oracle.grantRole(oracle.WRITER_ROLE(), address(proxy));
    }

    /// @dev Encode report for proxy - now uses UpdateInput struct encoding
    function _encodeProxyReport(
        string memory referenceId,
        uint256 supply_,
        int256 price_,
        uint256 state_,
        bytes32 updateTypeHash
    )
        internal
        pure
        returns (bytes memory)
    {
        ILlamaGuardOracle.UpdateInput memory input = ILlamaGuardOracle.UpdateInput({
            referenceId: referenceId,
            newValue: abi.encode(price_),
            updateTypeHash: updateTypeHash,
            additionalData: abi.encode(supply_, price_, state_)
        });
        return abi.encode(input);
    }

    function testProxyForwardsUpdates() public {
        // Build metadata matching expected values so onReport passes in base template
        bytes memory metadata = _buildMetadata(expectedWorkflowId, expectedAuthor, expectedWorkflowName);

        bytes memory report = _encodeProxyReport("ref-1", 1000, 321, 9, PRICE_HASH);

        proxy.onReport(metadata, report);

        // Verify via latestRoundData
        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, 321);

        // Verify full data via getUpdateById - decode from additionalData for full bundle
        ILlamaGuardOracle.RiskParameterUpdate memory update = oracle.getUpdateById(1);
        (uint256 supply, int256 price, uint256 state) = abi.decode(update.additionalData, (uint256, int256, uint256));
        assertEq(supply, 1000);
        assertEq(state, 9);
        assertEq(price, 321);
    }

    function testOnReportRevertsForWrongAuthor() public {
        bytes memory metadata = _buildMetadata(expectedWorkflowId, address(0xBEEF), expectedWorkflowName);
        bytes memory report = _encodeProxyReport("ref-1", 100, 200, 3, PRICE_HASH);

        vm.expectRevert();
        proxy.onReport(metadata, report);
    }

    function testOnReportRevertsForWrongWorkflow() public {
        bytes memory metadata = _buildMetadata(expectedWorkflowId, expectedAuthor, bytes10("WRONGNAME"));
        bytes memory report = _encodeProxyReport("ref-1", 500, 600, 7, PRICE_HASH);

        vm.expectRevert();
        proxy.onReport(metadata, report);
    }

    function testOnReportRevertsForInactiveWorkflow() public {
        // Deactivate the workflow
        vm.prank(owner);
        proxy.setWorkflowActive(expectedWorkflowId, false);

        bytes memory metadata = _buildMetadata(expectedWorkflowId, expectedAuthor, expectedWorkflowName);
        bytes memory report = _encodeProxyReport("ref-1", 500, 600, 7, PRICE_HASH);

        vm.expectRevert(abi.encodeWithSelector(AbstractCreReceiver.WorkflowNotActive.selector, expectedWorkflowId));
        proxy.onReport(metadata, report);
    }

    function testOnReportRevertsForUnknownWorkflow() public {
        bytes32 unknownWorkflowId = bytes32("UNKNOWN_WORKFLOW_ID____________");
        bytes memory metadata = _buildMetadata(unknownWorkflowId, expectedAuthor, expectedWorkflowName);
        bytes memory report = _encodeProxyReport("ref-1", 500, 600, 7, PRICE_HASH);

        vm.expectRevert(abi.encodeWithSelector(AbstractCreReceiver.WorkflowNotActive.selector, unknownWorkflowId));
        proxy.onReport(metadata, report);
    }

    function testSetLlamaGuardOracleRequiresWriteAccess() public {
        // New oracle without granting role to proxy should revert
        address[] memory noMarkets = new address[](0);
        LlamaGuardOracle newOracle = new LlamaGuardOracle(8, "New Feed", 1, defaultUpdateTypes, noMarkets);

        vm.prank(owner);
        vm.expectRevert(LlamaGuardOracleProxy.InvalidLlamaGuardOracle.selector);
        proxy.setLlamaGuardOracle(address(newOracle));

        // Grant write role and try again
        newOracle.grantRole(newOracle.WRITER_ROLE(), address(proxy));
        vm.prank(owner);
        proxy.setLlamaGuardOracle(address(newOracle));

        assertEq(address(proxy.llamaguardOracle()), address(newOracle));
    }

    function test_RevertWhen_ConstructorCalledWithZeroAddress() public {
        vm.expectRevert(LlamaGuardOracleProxy.InvalidLlamaGuardOracle.selector);
        new LlamaGuardOracleProxy(
            address(0), expectedWorkflowId, expectedForwarder, expectedAuthor, expectedWorkflowName, proxyDescription
        );
    }

    function test_SetIsReportWriteSecured_EnablesWriteSecurity() public {
        vm.startPrank(owner);
        // Disable security first
        proxy.setIsReportWriteSecured(false);
        assertFalse(proxy.isReportWriteSecured(), "Security should be disabled");

        // Re-enable security
        proxy.setIsReportWriteSecured(true);
        assertTrue(proxy.isReportWriteSecured(), "Security should be enabled");
        vm.stopPrank();
    }

    function test_SetIsReportWriteSecured_DisablesWriteSecurity() public {
        // Security is enabled by default
        assertTrue(proxy.isReportWriteSecured(), "Security should be enabled by default");

        // Disable security
        vm.prank(owner);
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
        vm.prank(owner);
        proxy.setIsReportWriteSecured(false);

        // Build metadata with wrong values - should not revert
        bytes memory wrongMetadata = _buildMetadata(bytes32("WRONG_ID"), address(0xDEAD), bytes10("WRONG"));
        bytes memory report = _encodeProxyReport("ref-1", 5000, 999, 7, PRICE_HASH);

        // Should succeed even with wrong metadata
        proxy.onReport(wrongMetadata, report);

        // Verify the update was processed via latestRoundData
        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, 999, "Price should be updated");

        // Verify full data via getUpdateById - decode from additionalData for full bundle
        ILlamaGuardOracle.RiskParameterUpdate memory update = oracle.getUpdateById(1);
        (uint256 supply, int256 price, uint256 state) = abi.decode(update.additionalData, (uint256, int256, uint256));
        assertEq(supply, 5000, "Supply should be updated");
        assertEq(state, 7, "State should be updated");
        assertEq(price, 999, "Price should be updated");
    }

    function test_Description_IsSetCorrectly() public view {
        assertEq(proxy.description(), proxyDescription, "Description should match constructor parameter");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // WORKFLOW CONFIG SETTER TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_SetWorkflowConfig_CreatesNewWorkflow() public {
        bytes32 newWorkflowId = bytes32("NEW_WORKFLOW_ID________________");
        address newForwarder = address(0x1111);
        address newAuthor = address(0x2222);
        bytes10 newName = bytes10("NEWWORKFLO");

        vm.prank(owner);
        proxy.setWorkflowConfig(newWorkflowId, newForwarder, newAuthor, newName, true);

        AbstractCreReceiver.WorkflowConfig memory config = proxy.getWorkflowConfig(newWorkflowId);
        assertEq(config.expectedForwarder, newForwarder, "Forwarder should be set");
        assertEq(config.expectedAuthor, newAuthor, "Author should be set");
        assertEq(config.expectedWorkflowName, newName, "Workflow name should be set");
        assertTrue(config.isActive, "Workflow should be active");
    }

    function test_SetWorkflowConfig_UpdatesExistingWorkflow() public {
        address newForwarder = address(0x3333);
        address newAuthor = address(0x4444);
        bytes10 newName = bytes10("UPDATEDNAM");

        vm.prank(owner);
        proxy.setWorkflowConfig(expectedWorkflowId, newForwarder, newAuthor, newName, true);

        AbstractCreReceiver.WorkflowConfig memory config = proxy.getWorkflowConfig(expectedWorkflowId);
        assertEq(config.expectedForwarder, newForwarder, "Forwarder should be updated");
        assertEq(config.expectedAuthor, newAuthor, "Author should be updated");
        assertEq(config.expectedWorkflowName, newName, "Workflow name should be updated");
        assertTrue(config.isActive, "Workflow should remain active");
    }

    function test_SetWorkflowConfig_EmitsEvent() public {
        bytes32 newWorkflowId = bytes32("EVENT_TEST_WORKFLOW____________");
        address newForwarder = address(0x5555);
        address newAuthor = address(0x6666);
        bytes10 newName = bytes10("EVENTTEST");

        vm.expectEmit(true, false, false, true);
        emit AbstractCreReceiver.WorkflowConfigUpdated(newWorkflowId, newForwarder, newAuthor, newName, true);

        vm.prank(owner);
        proxy.setWorkflowConfig(newWorkflowId, newForwarder, newAuthor, newName, true);
    }

    function test_RevertWhen_SetWorkflowConfig_CalledByNonOwner() public {
        address nonOwner = address(0xBEEF);

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        proxy.setWorkflowConfig(expectedWorkflowId, address(0x1), address(0x2), bytes10("NAME"), true);
    }

    function test_SetWorkflowActive_ActivatesWorkflow() public {
        vm.startPrank(owner);
        // First deactivate
        proxy.setWorkflowActive(expectedWorkflowId, false);
        assertFalse(proxy.isWorkflowActive(expectedWorkflowId), "Workflow should be inactive");

        // Then activate
        proxy.setWorkflowActive(expectedWorkflowId, true);
        assertTrue(proxy.isWorkflowActive(expectedWorkflowId), "Workflow should be active");
        vm.stopPrank();
    }

    function test_SetWorkflowActive_DeactivatesWorkflow() public {
        // Workflow is active by default from constructor
        assertTrue(proxy.isWorkflowActive(expectedWorkflowId), "Workflow should be active by default");

        // Deactivate
        vm.prank(owner);
        proxy.setWorkflowActive(expectedWorkflowId, false);
        assertFalse(proxy.isWorkflowActive(expectedWorkflowId), "Workflow should be inactive");
    }

    function test_SetWorkflowActive_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit AbstractCreReceiver.WorkflowConfigUpdated(
            expectedWorkflowId, expectedForwarder, expectedAuthor, expectedWorkflowName, false
        );

        vm.prank(owner);
        proxy.setWorkflowActive(expectedWorkflowId, false);
    }

    function test_RevertWhen_SetWorkflowActive_CalledByNonOwner() public {
        address nonOwner = address(0xBEEF);

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        proxy.setWorkflowActive(expectedWorkflowId, false);
    }

    function test_SetWorkflowConfig_VerifiesOnReport() public {
        // Set new workflow config with test address as forwarder
        bytes32 newWorkflowId = bytes32("NEW_WORKFLOW_CID_0123456789_____");
        address newAuthor = address(0xAA11);
        bytes10 newName = bytes10("NEWNAME");

        vm.prank(owner);
        proxy.setWorkflowConfig(newWorkflowId, address(this), newAuthor, newName, true);

        // Build metadata with new expected values
        bytes memory metadata = _buildMetadata(newWorkflowId, newAuthor, newName);
        bytes memory report = _encodeProxyReport("ref-new", 3000, 400, 5, PRICE_HASH);

        // Should succeed with new workflow config
        proxy.onReport(metadata, report);

        // Verify update was processed
        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, 400, "Price should be updated");
    }

    function test_MultipleWorkflows_CanCoexist() public {
        // Add a second workflow
        bytes32 secondWorkflowId = bytes32("SECOND_WORKFLOW_ID_____________");
        address secondAuthor = address(0xBB22);
        bytes10 secondName = bytes10("SECOND");

        vm.prank(owner);
        proxy.setWorkflowConfig(secondWorkflowId, address(this), secondAuthor, secondName, true);

        // First workflow should still work
        bytes memory metadata1 = _buildMetadata(expectedWorkflowId, expectedAuthor, expectedWorkflowName);
        bytes memory report1 = _encodeProxyReport("ref-1", 1000, 100, 1, PRICE_HASH);
        proxy.onReport(metadata1, report1);

        (, int256 answer1,,,) = oracle.latestRoundData();
        assertEq(answer1, 100, "First workflow update should work");

        // Second workflow should also work
        bytes memory metadata2 = _buildMetadata(secondWorkflowId, secondAuthor, secondName);
        bytes memory report2 = _encodeProxyReport("ref-2", 2000, 200, 2, PRICE_HASH);
        proxy.onReport(metadata2, report2);

        (, int256 answer2,,,) = oracle.latestRoundData();
        assertEq(answer2, 200, "Second workflow update should work");
    }

    function test_GetWorkflowConfig_ReturnsCorrectData() public view {
        AbstractCreReceiver.WorkflowConfig memory config = proxy.getWorkflowConfig(expectedWorkflowId);

        assertEq(config.expectedForwarder, expectedForwarder, "Forwarder should match");
        assertEq(config.expectedAuthor, expectedAuthor, "Author should match");
        assertEq(config.expectedWorkflowName, expectedWorkflowName, "Workflow name should match");
        assertTrue(config.isActive, "Workflow should be active");
    }

    function test_IsWorkflowActive_ReturnsCorrectStatus() public {
        assertTrue(proxy.isWorkflowActive(expectedWorkflowId), "Known workflow should be active");

        bytes32 unknownWorkflowId = bytes32("UNKNOWN_WORKFLOW_______________");
        assertFalse(proxy.isWorkflowActive(unknownWorkflowId), "Unknown workflow should be inactive");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // OWNABLE2STEP TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_TransferOwnership_SetsPendingOwner() public {
        address newOwner = address(0xEEFF33);

        vm.prank(owner);
        proxy.transferOwnership(newOwner);

        // Owner should still be the original owner
        assertEq(proxy.owner(), owner, "Owner should not change immediately");
        // Pending owner should be set
        assertEq(proxy.pendingOwner(), newOwner, "Pending owner should be set");
    }

    function test_AcceptOwnership_TransfersOwnership() public {
        address newOwner = address(0xEEFF33);

        // Step 1: Transfer ownership (sets pending owner)
        vm.prank(owner);
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

        vm.prank(owner);
        proxy.transferOwnership(newOwner);

        // Try to accept as random address (not pending owner)
        vm.prank(randomAddress);
        vm.expectRevert();
        proxy.acceptOwnership();
    }

    function test_TransferOwnership_ThenAccept_AllowsNewOwnerToCallOnlyOwner() public {
        address newOwner = address(0xEEFF33);

        // Transfer and accept ownership
        vm.prank(owner);
        proxy.transferOwnership(newOwner);
        vm.prank(newOwner);
        proxy.acceptOwnership();

        // New owner should be able to call onlyOwner functions
        vm.prank(newOwner);
        proxy.setWorkflowConfig(expectedWorkflowId, address(0xABCD), address(0x1234), bytes10("NEWNAME"), true);

        AbstractCreReceiver.WorkflowConfig memory config = proxy.getWorkflowConfig(expectedWorkflowId);
        assertEq(config.expectedForwarder, address(0xABCD), "New owner should be able to update workflow config");
    }

    function test_TransferOwnership_OldOwnerCannotCallOnlyOwner() public {
        address newOwner = address(0xEEFF33);

        // Transfer and accept ownership
        vm.prank(owner);
        proxy.transferOwnership(newOwner);
        vm.prank(newOwner);
        proxy.acceptOwnership();

        // Old owner should NOT be able to call onlyOwner functions
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        proxy.setWorkflowActive(expectedWorkflowId, false);
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
