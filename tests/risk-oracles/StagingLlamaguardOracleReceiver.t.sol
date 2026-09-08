// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";
import { IReceiver } from "@chainlink/contracts/src/v0.8/keystone/interfaces/IReceiver.sol";
import { StagingLlamaguardOracleReceiver } from "../../script/risk-oracles/sepolia/StagingLlamaguardOracleReceiver.sol";
import { MockRiskOracleSink } from "./mocks/MockRiskOracleSink.sol";

contract StagingLlamaguardOracleReceiverTest is Test {
    StagingLlamaguardOracleReceiver internal receiver;
    MockRiskOracleSink internal sink;

    address internal forwarder = makeAddr("forwarder");
    address internal attacker = makeAddr("attacker");
    bytes4 internal constant UPDATE_SELECTOR =
        bytes4(keccak256("updateLatestRiskRoundData((string,bytes,string,bytes,uint256))"));

    function setUp() public {
        sink = new MockRiskOracleSink();
        receiver = new StagingLlamaguardOracleReceiver(forwarder, address(sink), "staging-llamaguard");
    }

    function test_constructor_setsImmutableConfig() public view {
        assertEq(receiver.FORWARDER(), forwarder);
        assertEq(receiver.LLAMAGUARD_ORACLE(), address(sink));
        assertEq(receiver.UPDATE_SELECTOR(), UPDATE_SELECTOR);
    }

    function test_onReport_revertsIfCallerIsNotForwarder() public {
        vm.expectRevert(
            abi.encodeWithSelector(StagingLlamaguardOracleReceiver.InvalidForwarder.selector, attacker, forwarder)
        );
        vm.prank(attacker);
        receiver.onReport(hex"", hex"1234");
    }

    function test_onReport_forwardsSelectorAndReport() public {
        bytes memory report = abi.encode("round-1", bytes("payload"), "type", bytes("extra"), block.timestamp + 1);

        vm.prank(forwarder);
        receiver.onReport(hex"", report);

        assertEq(sink.callCount(), 1);
        assertEq(sink.lastSelector(), UPDATE_SELECTOR);

        bytes memory received = sink.lastCalldata();
        assertEq(received.length, 4 + report.length);
        for (uint256 i; i < report.length; i++) {
            assertEq(received[i + 4], report[i]);
        }
    }

    function test_onReport_bubblesPublishFailure() public {
        sink.setShouldRevert(true, bytes("boom"));

        vm.expectRevert(abi.encodeWithSelector(StagingLlamaguardOracleReceiver.PublishFailed.selector, bytes("boom")));
        vm.prank(forwarder);
        receiver.onReport(hex"", hex"1234");
    }

    function test_supportsIReceiverInterface() public view {
        assertTrue(receiver.supportsInterface(type(IReceiver).interfaceId));
    }
}
