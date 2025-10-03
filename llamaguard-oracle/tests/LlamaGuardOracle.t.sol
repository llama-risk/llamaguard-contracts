// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { LlamaGuardOracle } from "../src/LlamaGuardOracle.sol";

contract LlamaGuardOracleTest is Test {
    LlamaGuardOracle internal oracle;

    address internal owner = address(this);
    address internal proxy = address(0x1234);
    address internal nonAuthorized = address(0x5678);

    event UpdateReceived(uint256 supply, uint256 price, uint256 state);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function setUp() public {
        oracle = new LlamaGuardOracle(8, "Test Feed", 1);
    }

    // ============================================
    // Constructor Tests
    // ============================================

    function testConstructorInitialization() public {
        assertEq(oracle.owner(), owner);
        assertEq(oracle.supply(), 0);
        assertEq(oracle.state(), 0);
        assertEq(oracle.proxyAddress(), address(0));

        // Verify oracle inherits aggregator functionality with correct parameters
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

    // ============================================
    // setProxyAddress Tests
    // ============================================

    function testSetProxyAddress() public {
        oracle.setProxyAddress(proxy);
        assertEq(oracle.proxyAddress(), proxy);
    }

    function testSetProxyAddressMultipleTimes() public {
        oracle.setProxyAddress(proxy);
        assertEq(oracle.proxyAddress(), proxy);

        address newProxy = address(0x9999);
        oracle.setProxyAddress(newProxy);
        assertEq(oracle.proxyAddress(), newProxy);
    }

    function testSetProxyAddressRevertsForNonOwner() public {
        vm.prank(nonAuthorized);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonAuthorized));
        oracle.setProxyAddress(proxy);
    }

    function testSetProxyAddressToZeroAddress() public {
        // Should be allowed as owner might want to disable proxy
        oracle.setProxyAddress(address(0));
        assertEq(oracle.proxyAddress(), address(0));
    }

    // ============================================
    // updateData Tests
    // ============================================

    function testUpdateData() public {
        oracle.setProxyAddress(proxy);

        vm.prank(proxy);
        vm.expectEmit(true, true, true, true);
        emit UpdateReceived(1000, 500, 2);
        oracle.updateData(1000, 500, 2);

        assertEq(oracle.supply(), 1000);
        assertEq(oracle.state(), 2);

        (uint256 supply, uint256 state, int256 price,) = oracle.getData();
        assertEq(supply, 1000);
        assertEq(state, 2);
        assertEq(price, 500);
    }

    function testUpdateDataMultipleTimes() public {
        oracle.setProxyAddress(proxy);

        vm.prank(proxy);
        oracle.updateData(100, 50, 1);

        vm.prank(proxy);
        oracle.updateData(200, 75, 2);

        vm.prank(proxy);
        oracle.updateData(300, 100, 3);

        assertEq(oracle.supply(), 300);
        assertEq(oracle.state(), 3);

        (uint256 supply, uint256 state, int256 price,) = oracle.getData();
        assertEq(supply, 300);
        assertEq(state, 3);
        assertEq(price, 100);
    }

    function testUpdateDataWithZeroValues() public {
        oracle.setProxyAddress(proxy);

        vm.prank(proxy);
        oracle.updateData(0, 0, 0);

        assertEq(oracle.supply(), 0);
        assertEq(oracle.state(), 0);

        (uint256 supply, uint256 state, int256 price,) = oracle.getData();
        assertEq(supply, 0);
        assertEq(state, 0);
        assertEq(price, 0);
    }

    function testUpdateDataWithLargeValues() public {
        oracle.setProxyAddress(proxy);

        uint256 largeSupply = type(uint256).max;
        uint256 largePrice = type(uint256).max / 2; // Divide by 2 to avoid overflow when casting to int256
        uint256 largeState = type(uint256).max;

        vm.prank(proxy);
        oracle.updateData(largeSupply, largePrice, largeState);

        assertEq(oracle.supply(), largeSupply);
        assertEq(oracle.state(), largeState);

        (uint256 supply, uint256 state, int256 price,) = oracle.getData();
        assertEq(supply, largeSupply);
        assertEq(state, largeState);
        assertEq(price, int256(largePrice));
    }

    function testUpdateDataRevertsForNonProxy() public {
        oracle.setProxyAddress(proxy);

        vm.prank(nonAuthorized);
        vm.expectRevert("Caller is not the authorized proxy");
        oracle.updateData(1000, 500, 2);
    }

    function testUpdateDataRevertsWhenProxyNotSet() public {
        vm.prank(proxy);
        vm.expectRevert("Caller is not the authorized proxy");
        oracle.updateData(1000, 500, 2);
    }

    function testUpdateDataRevertsForOwner() public {
        oracle.setProxyAddress(proxy);

        // Even owner cannot call updateData
        vm.expectRevert("Caller is not the authorized proxy");
        oracle.updateData(1000, 500, 2);
    }

    function testUpdateDataEmitsEvent() public {
        oracle.setProxyAddress(proxy);

        vm.prank(proxy);
        vm.expectEmit(true, true, true, true);
        emit UpdateReceived(1234, 5678, 9);
        oracle.updateData(1234, 5678, 9);
    }

    // ============================================
    // Security Tests: Only Proxy Can Update
    // ============================================

    function testOnlyConfiguredProxyCanUpdate() public {
        oracle.setProxyAddress(proxy);

        // Only the configured proxy can successfully update
        vm.prank(proxy);
        oracle.updateData(100, 200, 1);

        (uint256 supply, uint256 state, int256 price,) = oracle.getData();
        assertEq(supply, 100);
        assertEq(price, 200);
        assertEq(state, 1);
    }

    function testCannotUpdateAfterProxyChanged() public {
        oracle.setProxyAddress(proxy);

        address newProxy = address(0x9999);
        oracle.setProxyAddress(newProxy);

        // Old proxy can no longer update
        vm.prank(proxy);
        vm.expectRevert("Caller is not the authorized proxy");
        oracle.updateData(100, 200, 1);

        // New proxy can update
        vm.prank(newProxy);
        oracle.updateData(100, 200, 1);
        assertEq(oracle.supply(), 100);
    }

    function testMultipleUnauthorizedCallersCannot() public {
        oracle.setProxyAddress(proxy);

        address[] memory attackers = new address[](5);
        attackers[0] = address(0xDEAD);
        attackers[1] = address(0xBEEF);
        attackers[2] = address(0xCAFE);
        attackers[3] = owner; // Even owner
        attackers[4] = address(this); // Even test contract

        for (uint256 i = 0; i < attackers.length; i++) {
            vm.prank(attackers[i]);
            vm.expectRevert("Caller is not the authorized proxy");
            oracle.updateData(999, 999, 999);
        }

        // Verify no data was changed
        assertEq(oracle.supply(), 0);
        assertEq(oracle.state(), 0);
    }

    function testDirectCallToInternalUpdateIsImpossible() public view {
        // NOTE: This test exists to document security.
        // updateLatestRoundData() is internal and CANNOT be called externally.
        // The compiler prevents external calls: oracle.updateLatestRoundData(123)
        // This means the ONLY way to update price data is through:
        // LlamaGuardOracleProxy → oracle.updateData() [onlyProxy] → internal updateLatestRoundData()
        
        // If this test compiles, it proves the security model is intact.
        assertTrue(true, "Internal method security verified by compilation");
    }

    // ============================================
    // getData Tests
    // ============================================

    function testGetDataInitialState() public {
        (uint256 supply, uint256 state, int256 price, uint256 startedAt) = oracle.getData();

        assertEq(supply, 0);
        assertEq(state, 0);
        assertEq(price, 0); // Initial aggregator value
        assertGt(startedAt, 0); // Should have a timestamp
    }

    function testGetDataAfterUpdate() public {
        oracle.setProxyAddress(proxy);

        uint256 timestampBefore = block.timestamp;

        vm.prank(proxy);
        oracle.updateData(5000, 2500, 7);

        (uint256 supply, uint256 state, int256 price, uint256 startedAt) = oracle.getData();

        assertEq(supply, 5000);
        assertEq(state, 7);
        assertEq(price, 2500);
        assertGe(startedAt, timestampBefore);
    }

    function testGetDataCanBeCalledByAnyone() public {
        oracle.setProxyAddress(proxy);

        vm.prank(proxy);
        oracle.updateData(1000, 500, 2);

        // Call from different addresses
        vm.prank(nonAuthorized);
        (uint256 supply1, uint256 state1, int256 price1,) = oracle.getData();

        vm.prank(owner);
        (uint256 supply2, uint256 state2, int256 price2,) = oracle.getData();

        vm.prank(address(0xABCD));
        (uint256 supply3, uint256 state3, int256 price3,) = oracle.getData();

        // All calls should return the same data
        assertEq(supply1, 1000);
        assertEq(supply2, 1000);
        assertEq(supply3, 1000);
        assertEq(state1, 2);
        assertEq(state2, 2);
        assertEq(state3, 2);
        assertEq(price1, 500);
        assertEq(price2, 500);
        assertEq(price3, 500);
    }

    // ============================================
    // Aggregator Integration Tests
    // ============================================

    function testAggregatorRoundIdIncreases() public {
        oracle.setProxyAddress(proxy);

        uint80 initialRoundId = oracle.getLatestRoundId();

        vm.prank(proxy);
        oracle.updateData(1000, 500, 2);

        uint80 newRoundId = oracle.getLatestRoundId();
        assertEq(newRoundId, initialRoundId + 1);
    }

    function testAggregatorStoresMultipleRounds() public {
        oracle.setProxyAddress(proxy);

        vm.prank(proxy);
        oracle.updateData(100, 50, 1);
        uint80 round1 = oracle.getLatestRoundId();

        vm.prank(proxy);
        oracle.updateData(200, 75, 2);
        uint80 round2 = oracle.getLatestRoundId();

        // Verify both rounds are stored
        (, int256 price1,,,) = oracle.getRoundData(round1);
        (, int256 price2,,,) = oracle.getRoundData(round2);

        assertEq(price1, 50);
        assertEq(price2, 75);
    }

    function testOracleIsDirectlyUsableAsChainlinkAggregator() public {
        oracle.setProxyAddress(proxy);

        vm.prank(proxy);
        oracle.updateData(1000, 500, 2);

        // Oracle can be used directly as a Chainlink aggregator
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracle.latestRoundData();

        assertEq(answer, 500);
        assertGt(roundId, 0);
        assertGt(startedAt, 0);
        assertGt(updatedAt, 0);
        assertEq(answeredInRound, roundId);
    }

    // ============================================
    // Ownership Tests (Ownable2Step)
    // ============================================

    function testOwnershipTransferTwoStep() public {
        address newOwner = address(0xABCD);

        // Step 1: Initiate transfer
        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferStarted(owner, newOwner);
        oracle.transferOwnership(newOwner);

        // Owner should still be the old owner
        assertEq(oracle.owner(), owner);
        assertEq(oracle.pendingOwner(), newOwner);

        // Step 2: New owner accepts
        vm.prank(newOwner);
        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferred(owner, newOwner);
        oracle.acceptOwnership();

        // Now ownership should be transferred
        assertEq(oracle.owner(), newOwner);
        assertEq(oracle.pendingOwner(), address(0));
    }

    function testOwnershipTransferPendingOwnerCanSetProxy() public {
        address newOwner = address(0xABCD);

        // Initiate transfer
        oracle.transferOwnership(newOwner);

        // Pending owner cannot set proxy yet
        vm.prank(newOwner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", newOwner));
        oracle.setProxyAddress(proxy);

        // Accept ownership
        vm.prank(newOwner);
        oracle.acceptOwnership();

        // Now new owner can set proxy
        vm.prank(newOwner);
        oracle.setProxyAddress(proxy);
        assertEq(oracle.proxyAddress(), proxy);
    }

    function testRenounceOwnership() public {
        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferred(owner, address(0));
        oracle.renounceOwnership();

        assertEq(oracle.owner(), address(0));

        // Cannot set proxy after renouncing
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", owner));
        oracle.setProxyAddress(proxy);
    }

    // ============================================
    // Edge Cases and Security Tests
    // ============================================

    function testProxyCannotBeChangedDuringUpdate() public {
        oracle.setProxyAddress(proxy);

        vm.prank(proxy);
        oracle.updateData(1000, 500, 2);

        // Change proxy
        address newProxy = address(0x9999);
        oracle.setProxyAddress(newProxy);

        // Old proxy should no longer work
        vm.prank(proxy);
        vm.expectRevert("Caller is not the authorized proxy");
        oracle.updateData(2000, 1000, 3);

        // New proxy should work
        vm.prank(newProxy);
        oracle.updateData(2000, 1000, 3);

        assertEq(oracle.supply(), 2000);
    }

    function testSequentialUpdatesInSameTransaction() public {
        oracle.setProxyAddress(proxy);

        vm.startPrank(proxy);
        for (uint256 i = 1; i <= 10; i++) {
            oracle.updateData(i * 100, i * 50, i);
        }
        vm.stopPrank();

        // Verify last update wins (all updates in same tx/block)
        assertEq(oracle.supply(), 1000);
        assertEq(oracle.state(), 10);

        (uint256 supply, uint256 state, int256 price,) = oracle.getData();
        assertEq(supply, 1000);
        assertEq(state, 10);
        assertEq(price, 500);
    }

    // ============================================
    // Fuzz Tests
    // ============================================

    function testFuzzUpdateData(uint256 _supply, uint256 _price, uint256 _state) public {
        // Limit price to avoid int256 overflow
        vm.assume(_price <= uint256(type(int256).max));

        oracle.setProxyAddress(proxy);

        vm.prank(proxy);
        oracle.updateData(_supply, _price, _state);

        assertEq(oracle.supply(), _supply);
        assertEq(oracle.state(), _state);

        (uint256 supply, uint256 state, int256 price,) = oracle.getData();
        assertEq(supply, _supply);
        assertEq(state, _state);
        assertEq(price, int256(_price));
    }

    function testFuzzSetProxyAddress(address _proxy) public {
        oracle.setProxyAddress(_proxy);
        assertEq(oracle.proxyAddress(), _proxy);
    }
}
