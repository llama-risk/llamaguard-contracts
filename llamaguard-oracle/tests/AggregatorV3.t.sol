// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { AggregatorV3 } from "../src/AggregatorV3.sol";

contract AggregatorV3Test is Test {
    AggregatorV3 internal aggregator;

    function setUp() public {
        aggregator = new AggregatorV3(8, "Mock Feed", 1);
    }

    function testInitialValues() public view {
        assertEq(aggregator.decimals(), 8);
        assertEq(aggregator.description(), "Mock Feed");
        assertEq(aggregator.version(), 1);

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            aggregator.latestRoundData();
        assertEq(roundId, 1);
        assertEq(answer, 0);
        assertGt(startedAt, 0);
        assertGt(updatedAt, 0);
        assertEq(answeredInRound, 1);
        assertEq(aggregator.getLatestRoundId(), 1);
    }

    function testUpdateLatestRoundData() public {
        aggregator.updateLatestRoundData(123);

        (uint80 roundId, int256 answer,,, uint80 answeredInRound) = aggregator.latestRoundData();
        assertEq(answer, 123);
        assertEq(roundId, 2);
        assertEq(answeredInRound, 2);
        assertEq(aggregator.getLatestRoundId(), 2);
    }

    function testUpdateRoundData() public {
        aggregator.updateLatestRoundData(111);
        uint80 lr = aggregator.getLatestRoundId();

        aggregator.updateRoundData(lr, 222);
        (uint80 roundId, int256 answer,,,) = aggregator.getRoundData(lr);
        assertEq(roundId, lr);
        assertEq(answer, 222);
    }

    function testGetRoundDataRevertsForMissing() public {
        vm.expectRevert(bytes("Round not found"));
        aggregator.getRoundData(99);
    }
}
