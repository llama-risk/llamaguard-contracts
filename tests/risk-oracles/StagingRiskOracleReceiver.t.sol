// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";
import { IReceiver } from "@chainlink/contracts/src/v0.8/keystone/interfaces/IReceiver.sol";
import { StagingRiskOracleReceiver } from "../../script/risk-oracles/sepolia/StagingRiskOracleReceiver.sol";
import { MockRiskOracleSink } from "./mocks/MockRiskOracleSink.sol";

contract StagingRiskOracleReceiverTest is Test {
    StagingRiskOracleReceiver internal receiver;
    MockRiskOracleSink internal sink;

    address internal forwarder = makeAddr("forwarder");
    address internal attacker = makeAddr("attacker");
    bytes4 internal selector = bytes4(keccak256("publishRiskParameterUpdate(bytes)"));

    function setUp() public {
        sink = new MockRiskOracleSink();
        receiver = new StagingRiskOracleReceiver(forwarder, address(sink), selector, "staging-single");
    }

    function test_constructor_setsImmutableConfig() public view {
        assertEq(receiver.FORWARDER(), forwarder);
        assertEq(receiver.RISK_ORACLE(), address(sink));
        assertEq(receiver.PUBLISH_SELECTOR(), selector);
    }

    function test_onReport_revertsIfCallerIsNotForwarder() public {
        vm.expectRevert(
            abi.encodeWithSelector(StagingRiskOracleReceiver.InvalidForwarder.selector, attacker, forwarder)
        );
        vm.prank(attacker);
        receiver.onReport(hex"", hex"1234");
    }

    function test_onReport_forwardsSelectorAndReport() public {
        bytes memory report = abi.encode("round-1", bytes("payload"), "type", address(0xBEEF), bytes("extra"));

        vm.prank(forwarder);
        receiver.onReport(hex"", report);

        assertEq(sink.callCount(), 1);
        assertEq(sink.lastSelector(), selector);

        bytes memory received = sink.lastCalldata();
        assertEq(received.length, 4 + report.length);
        for (uint256 i; i < report.length; i++) {
            assertEq(received[i + 4], report[i]);
        }
    }

    function test_onReport_bubblesPublishFailure() public {
        sink.setShouldRevert(true, bytes("boom"));

        vm.expectRevert(abi.encodeWithSelector(StagingRiskOracleReceiver.PublishFailed.selector, bytes("boom")));
        vm.prank(forwarder);
        receiver.onReport(hex"", hex"1234");
    }

    function test_supportsIReceiverInterface() public view {
        assertTrue(receiver.supportsInterface(type(IReceiver).interfaceId));
    }
}
