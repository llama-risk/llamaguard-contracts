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

  function setUp() public {
    oracle = new LlamaGuardOracle(8, "Mock Feed", 1);
    proxy = new LlamaGuardOracleProxy(address(oracle), expectedAuthor, expectedWorkflowName);

    vm.prank(owner);
    oracle.setProxyAddress(address(proxy));
  }

  function testProxyForwardsUpdates() public {
    // Build metadata matching expected values so onReport passes in base template
    bytes memory metadata = _buildMetadata(expectedAuthor, expectedWorkflowName);

    LlamaGuardOracleProxy.Update memory u = LlamaGuardOracleProxy.Update({ supply: 1000, price: 321, state: 9 });
    bytes memory report = abi.encode(u);

    proxy.onReport(metadata, report);

    (uint256 supply, uint256 state, int256 price, ) = oracle.getData();
    assertEq(supply, 1000);
    assertEq(state, 9);
    assertEq(price, 321);
  }

  function testOnReportRevertsForWrongAuthor() public {
    bytes memory metadata = _buildMetadata(address(0xBEEF), expectedWorkflowName);
    bytes memory report = abi.encode(LlamaGuardOracleProxy.Update({ supply: 1, price: 2, state: 3 }));

    vm.expectRevert();
    proxy.onReport(metadata, report);
  }

  function testOnReportRevertsForWrongWorkflow() public {
    bytes memory metadata = _buildMetadata(expectedAuthor, bytes10("WRONGNAME"));
    bytes memory report = abi.encode(LlamaGuardOracleProxy.Update({ supply: 1, price: 2, state: 3 }));

    vm.expectRevert();
    proxy.onReport(metadata, report);
  }

  function _buildMetadata(address workflowOwner, bytes10 workflowName) internal pure returns (bytes memory) {
    bytes memory workflowCid = new bytes(32);
    bytes memory reportName = new bytes(2);
    return abi.encodePacked(workflowCid, workflowName, bytes20(workflowOwner), reportName);
  }
}


