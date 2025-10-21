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
    bytes10 internal expectedWorkflowName = bytes10("WORKFLOW1");
    string internal proxyDescription = "Proxy: Mock Feed";

    function setUp() public {
        oracle = new LlamaGuardOracle(8, "Mock Feed", 1);
        proxy = new LlamaGuardOracleProxy(address(oracle), expectedAuthor, expectedWorkflowName, proxyDescription);

        // Grant writer role to proxy so it can forward updates
        oracle.grantRole(oracle.WRITER_ROLE(), address(proxy));
    }

    function testProxyForwardsUpdates() public {
        // Build metadata matching expected values so onReport passes in base template
        bytes memory metadata = _buildMetadata(expectedAuthor, expectedWorkflowName);

        bytes memory report = abi.encode(LlamaGuardOracle.UpdateData({ supply: 1000, price: 321, state: 9 }));

        proxy.onReport(metadata, report);

        (uint256 supply, uint256 state, int256 price,) = oracle.getData();
        assertEq(supply, 1000);
        assertEq(state, 9);
        assertEq(price, 321);
    }

    function testOnReportRevertsForWrongAuthor() public {
        bytes memory metadata = _buildMetadata(address(0xBEEF), expectedWorkflowName);
        bytes memory report = abi.encode(LlamaGuardOracle.UpdateData({ supply: 100, price: 200, state: 3 }));

        vm.expectRevert();
        proxy.onReport(metadata, report);
    }

    function testOnReportRevertsForWrongWorkflow() public {
        bytes memory metadata = _buildMetadata(expectedAuthor, bytes10("WRONGNAME"));
        bytes memory report = abi.encode(LlamaGuardOracle.UpdateData({ supply: 500, price: 600, state: 7 }));

        vm.expectRevert();
        proxy.onReport(metadata, report);
    }

    function testChangeLlamaGuardOracleRequiresWriteAccess() public {
        // New oracle without granting role to proxy should revert
        LlamaGuardOracle newOracle = new LlamaGuardOracle(8, "New Feed", 1);

        vm.expectRevert(LlamaGuardOracleProxy.InvalidLlamaGuardOracle.selector);
        proxy.changeLlamaGuardOracle(address(newOracle));

        // Grant write role and try again
        newOracle.grantRole(newOracle.WRITER_ROLE(), address(proxy));
        proxy.changeLlamaGuardOracle(address(newOracle));

        assertEq(address(proxy.llamaguardOracle()), address(newOracle));
    }

    function _buildMetadata(address workflowOwner, bytes10 workflowName) internal pure returns (bytes memory) {
        bytes memory workflowCid = new bytes(32);
        bytes memory reportName = new bytes(2);
        return abi.encodePacked(workflowCid, workflowName, bytes20(workflowOwner), reportName);
    }
}
