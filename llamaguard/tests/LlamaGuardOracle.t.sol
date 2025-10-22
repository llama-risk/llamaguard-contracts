// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { LlamaGuardOracle } from "../src/LlamaGuardOracle.sol";

contract LlamaGuardOracleTest is Test {
    LlamaGuardOracle internal oracle;

    address internal admin = address(this);
    address internal writer = address(0x1234);
    address internal nonWriter = address(0x5678);

    event UpdateReceived(uint256 supply, uint256 price, uint256 state);

    function setUp() public {
        oracle = new LlamaGuardOracle(8, "Test Feed", 1);
    }

    function _encodeUpdate(uint256 supply_, uint256 price_, uint256 state_) internal pure returns (bytes memory) {
        return abi.encode(LlamaGuardOracle.UpdateData({ supply: supply_, price: price_, state: state_ }));
    }

    // Constructor
    function testConstructorInitialization() public {
        assertEq(oracle.supply(), 0);
        assertEq(oracle.state(), 0);
        assertEq(oracle.decimals(), 8);
        assertEq(oracle.description(), "Test Feed");
        assertEq(oracle.version(), 1);
    }

    function testConstructorWithDifferentParameters() public {
        LlamaGuardOracle newOracle = new LlamaGuardOracle(18, "ETH/USD", 2);
        assertEq(newOracle.decimals(), 18);
        assertEq(newOracle.description(), "ETH/USD");
        assertEq(newOracle.version(), 2);
    }

    // updateData
    function testUpdateDataByWriter() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        vm.expectEmit(true, true, true, true);
        emit UpdateReceived(1000, 500, 2);
        oracle.updateData(_encodeUpdate(1000, 500, 2));

        assertEq(oracle.supply(), 1000);
        assertEq(oracle.state(), 2);

        (uint256 supply, uint256 state, int256 price,) = oracle.getData();
        assertEq(supply, 1000);
        assertEq(state, 2);
        assertEq(price, 500);
    }

    function testUpdateDataRevertsForNonWriter() public {
        vm.prank(nonWriter);
        vm.expectRevert();
        oracle.updateData(_encodeUpdate(1000, 500, 2));
    }

    function testUpdateDataMultipleTimes() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        vm.startPrank(writer);
        oracle.updateData(_encodeUpdate(100, 50, 1));
        oracle.updateData(_encodeUpdate(200, 75, 2));
        oracle.updateData(_encodeUpdate(300, 100, 3));
        vm.stopPrank();

        assertEq(oracle.supply(), 300);
        assertEq(oracle.state(), 3);
        (uint256 s, uint256 st, int256 p,) = oracle.getData();
        assertEq(s, 300);
        assertEq(st, 3);
        assertEq(p, 100);
    }

    function testUpdateDataWithZeroValues() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        vm.prank(writer);
        oracle.updateData(_encodeUpdate(0, 0, 0));

        assertEq(oracle.supply(), 0);
        assertEq(oracle.state(), 0);
        (uint256 s, uint256 st, int256 p,) = oracle.getData();
        assertEq(s, 0);
        assertEq(st, 0);
        assertEq(p, 0);
    }

    function testUpdateDataWithLargeValues() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        uint256 largeSupply = type(uint256).max;
        uint256 largePrice = uint256(type(int256).max);
        uint256 largeState = type(uint256).max;

        vm.prank(writer);
        oracle.updateData(_encodeUpdate(largeSupply, largePrice, largeState));

        assertEq(oracle.supply(), largeSupply);
        assertEq(oracle.state(), largeState);
        (uint256 s, uint256 st, int256 p,) = oracle.getData();
        assertEq(s, largeSupply);
        assertEq(st, largeState);
        assertEq(p, int256(largePrice));
    }

    // getData
    function testGetDataInitialState() public {
        (uint256 s, uint256 st, int256 p, uint256 startedAt) = oracle.getData();
        assertEq(s, 0);
        assertEq(st, 0);
        assertEq(p, 0);
        assertGt(startedAt, 0);
    }

    function testGetDataAfterUpdate() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        uint256 beforeTs = block.timestamp;
        vm.prank(writer);
        oracle.updateData(_encodeUpdate(5000, 2500, 7));
        (uint256 s, uint256 st, int256 p, uint256 startedAt) = oracle.getData();
        assertEq(s, 5000);
        assertEq(st, 7);
        assertEq(p, 2500);
        assertGe(startedAt, beforeTs);
    }

    function testGetDataCallableByAnyone() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        vm.prank(writer);
        oracle.updateData(_encodeUpdate(1000, 500, 2));

        vm.prank(nonWriter);
        (uint256 s1, uint256 st1, int256 p1,) = oracle.getData();
        vm.prank(admin);
        (uint256 s2, uint256 st2, int256 p2,) = oracle.getData();
        vm.prank(address(0xABCD));
        (uint256 s3, uint256 st3, int256 p3,) = oracle.getData();
        assertEq(s1, 1000);
        assertEq(s2, 1000);
        assertEq(s3, 1000);
        assertEq(st1, 2);
        assertEq(st2, 2);
        assertEq(st3, 2);
        assertEq(p1, 500);
        assertEq(p2, 500);
        assertEq(p3, 500);
    }

    // Aggregator integration
    function testAggregatorRoundIdIncreases() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        uint80 initialId = oracle.getLatestRoundId();
        vm.prank(writer);
        oracle.updateData(_encodeUpdate(1000, 500, 2));
        uint80 newId = oracle.getLatestRoundId();
        assertEq(newId, initialId + 1);
    }

    function testAggregatorStoresMultipleRounds() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        vm.startPrank(writer);
        oracle.updateData(_encodeUpdate(100, 50, 1));
        uint80 r1 = oracle.getLatestRoundId();
        oracle.updateData(_encodeUpdate(200, 75, 2));
        uint80 r2 = oracle.getLatestRoundId();
        vm.stopPrank();

        (, int256 p1,,,) = oracle.getRoundData(r1);
        (, int256 p2,,,) = oracle.getRoundData(r2);
        assertEq(p1, 50);
        assertEq(p2, 75);
    }

    function testOracleIsChainlinkAggregator() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        vm.prank(writer);
        oracle.updateData(_encodeUpdate(1000, 500, 2));
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracle.latestRoundData();
        assertEq(answer, 500);
        assertGt(roundId, 0);
        assertGt(startedAt, 0);
        assertGt(updatedAt, 0);
        assertGt(answeredInRound, 0);
    }

    function testSequentialUpdatesInSameTransaction() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        vm.startPrank(writer);
        for (uint256 i = 1; i <= 10; i++) {
            oracle.updateData(_encodeUpdate(i * 100, i * 50, i));
        }
        vm.stopPrank();

        assertEq(oracle.supply(), 1000);
        assertEq(oracle.state(), 10);
        (uint256 s, uint256 st, int256 p,) = oracle.getData();
        assertEq(s, 1000);
        assertEq(st, 10);
        assertEq(p, 500);
    }

    // Fuzz
    function testFuzzUpdateData(uint256 _supply, uint256 _price, uint256 _state) public {
        vm.assume(_price <= uint256(type(int256).max));
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        vm.prank(writer);
        oracle.updateData(_encodeUpdate(_supply, _price, _state));
        assertEq(oracle.supply(), _supply);
        assertEq(oracle.state(), _state);
        (uint256 s, uint256 st, int256 p,) = oracle.getData();
        assertEq(s, _supply);
        assertEq(st, _state);
        assertEq(p, int256(_price));
    }
}
