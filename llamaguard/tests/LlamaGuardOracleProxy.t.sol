// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { LlamaGuardOracle } from "../src/LlamaGuardOracle.sol";
import { LlamaGuardOracleProxy } from "../src/LlamaGuardOracleProxy.sol";

contract LlamaGuardOracleProxyTest is Test {
    LlamaGuardOracle internal oracle;
    LlamaGuardOracleProxy internal proxy;

    address internal owner = address(this);
    address internal expectedAuthor = address(0xA11CE);
    address internal expectedForwarder;
    bytes10 internal expectedWorkflowName = bytes10("WORKFLOW1");
    bytes32 internal expectedWorkflowId = bytes32("WORKFLOWCID_ABCDEFGHIJKLMNOPQRST");
    string internal proxyDescription = "Proxy: Mock Feed";

    function setUp() public {
        expectedForwarder = address(this); // in tests, we call onReport directly
        oracle = new LlamaGuardOracle(8, "Mock Feed", 1);
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

    function testProxyForwardsUpdates() public {
        // Build metadata matching expected values so onReport passes in base template
        bytes memory metadata = _buildMetadata(expectedWorkflowId, expectedAuthor, expectedWorkflowName);

        bytes memory report = abi.encode(LlamaGuardOracle.UpdateData({ supply: 1000, price: 321, state: 9 }));

        proxy.onReport(metadata, report);

        (uint256 supply, uint256 state, int256 price,) = oracle.getData();
        assertEq(supply, 1000);
        assertEq(state, 9);
        assertEq(price, 321);
    }

    function testOnReportRevertsForWrongAuthor() public {
        bytes memory metadata = _buildMetadata(expectedWorkflowId, address(0xBEEF), expectedWorkflowName);
        bytes memory report = abi.encode(LlamaGuardOracle.UpdateData({ supply: 100, price: 200, state: 3 }));

        vm.expectRevert();
        proxy.onReport(metadata, report);
    }

    function testOnReportRevertsForWrongWorkflow() public {
        bytes memory metadata = _buildMetadata(expectedWorkflowId, expectedAuthor, bytes10("WRONGNAME"));
        bytes memory report = abi.encode(LlamaGuardOracle.UpdateData({ supply: 500, price: 600, state: 7 }));

        vm.expectRevert();
        proxy.onReport(metadata, report);
    }

    function testSetLlamaGuardOracleRequiresWriteAccess() public {
        // New oracle without granting role to proxy should revert
        LlamaGuardOracle newOracle = new LlamaGuardOracle(8, "New Feed", 1);

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
            address(0),
            expectedAuthor,
            expectedForwarder,
            expectedWorkflowName,
            expectedWorkflowId,
            proxyDescription
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
        bytes memory report = abi.encode(LlamaGuardOracle.UpdateData({ supply: 5000, price: 999, state: 7 }));

        // Should succeed even with wrong metadata
        proxy.onReport(wrongMetadata, report);

        // Verify the update was processed
        (uint256 supply, uint256 state, int256 price,) = oracle.getData();
        assertEq(supply, 5000, "Supply should be updated");
        assertEq(state, 7, "State should be updated");
        assertEq(price, 999, "Price should be updated");
    }

    function test_Description_IsSetCorrectly() public view {
        assertEq(proxy.description(), proxyDescription, "Description should match constructor parameter");
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
