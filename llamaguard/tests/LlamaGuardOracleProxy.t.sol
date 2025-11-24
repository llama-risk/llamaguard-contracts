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

    function _encodeProxyReport(
        string memory referenceId,
        uint256 supply_,
        int256 price_,
        uint256 state_,
        string memory updateType,
        address market,
        bytes memory additionalData
    )
        internal
        pure
        returns (bytes memory)
    {
        bytes memory newValue = abi.encode(supply_, price_, state_);
        return abi.encode(referenceId, newValue, updateType, market, additionalData);
    }

    function testProxyForwardsUpdates() public {
        // Build metadata matching expected values so onReport passes in base template
        bytes memory metadata = _buildMetadata(expectedWorkflowId, expectedAuthor, expectedWorkflowName);

        bytes memory report = _encodeProxyReport("ref-1", 1000, 321, 9, "price", defaultMarket, "");

        proxy.onReport(metadata, report);

        (uint256 supply, uint256 state, int256 price,) = oracle.getData();
        assertEq(supply, 1000);
        assertEq(state, 9);
        assertEq(price, 321);
    }

    function testOnReportRevertsForWrongAuthor() public {
        bytes memory metadata = _buildMetadata(expectedWorkflowId, address(0xBEEF), expectedWorkflowName);
        bytes memory report = _encodeProxyReport("ref-1", 100, 200, 3, "price", defaultMarket, "");

        vm.expectRevert();
        proxy.onReport(metadata, report);
    }

    function testOnReportRevertsForWrongWorkflow() public {
        bytes memory metadata = _buildMetadata(expectedWorkflowId, expectedAuthor, bytes10("WRONGNAME"));
        bytes memory report = _encodeProxyReport("ref-1", 500, 600, 7, "price", defaultMarket, "");

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
        bytes memory report = _encodeProxyReport("ref-1", 5000, 999, 7, "price", defaultMarket, "");

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
