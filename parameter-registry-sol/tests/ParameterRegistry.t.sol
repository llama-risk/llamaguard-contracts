// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.26 <0.9.0;

import { Test } from "forge-std/src/Test.sol";
import { ParameterRegistry } from "../src/ParameterRegistry.sol";
import { MockAggregatorV3 } from "./mocks/MockAggregatorV3.sol";
import { MockOracleProxy } from "./mocks/MockOracleProxy.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { stdStorage, StdStorage } from "forge-std/src/StdStorage.sol";

contract ParameterRegistryTest is Test {
    using stdStorage for StdStorage;

    ParameterRegistry internal registry;
    MockAggregatorV3 internal mockAggregator;
    MockAggregatorV3 internal mockAggregatorWithZeroRoundId;
    MockOracleProxy internal mockOracleProxy;
    MockOracleProxy internal mockOracleProxyWithZeroRoundId;
    address internal owner;
    address internal updater;
    address internal asset1;
    address internal asset2;
    address internal nonOwner;
    address internal nonUpdater;

    function setUp() public {
        owner = makeAddr("owner");
        updater = makeAddr("updater");
        asset1 = makeAddr("asset1");
        asset2 = makeAddr("asset2");
        nonOwner = makeAddr("nonOwner");
        nonUpdater = makeAddr("nonUpdater");

        vm.prank(owner);
        registry = new ParameterRegistry(owner, updater);

        // Deploy mock aggregators
        mockAggregator = new MockAggregatorV3();
        mockAggregatorWithZeroRoundId = new MockAggregatorV3();

        // Deploy mock oracle proxies pointing to the aggregators
        mockOracleProxy = new MockOracleProxy(address(mockAggregator));
        mockOracleProxyWithZeroRoundId = new MockOracleProxy(address(mockAggregatorWithZeroRoundId));

        // Set up some mock round data
        for (uint80 i = 1; i <= 100; i++) {
            mockAggregator.setRoundData(
                i,
                int256(uint256(i) * 1e8), // answer
                block.timestamp - (100 - i) * 3600, // startedAt
                block.timestamp - (100 - i) * 3600, // updatedAt
                i // answeredInRound
            );
        }

        mockAggregatorWithZeroRoundId.setRoundData(0, int256(uint256(1) * 1e8), block.timestamp, block.timestamp, 0);
    }

    function test_ConstructorSetsOwnerAndUpdater() public view {
        assertEq(registry.owner(), owner);
        assertEq(registry.updater(), updater);
    }

    function test_ConstructorRevertsWithZeroUpdater() public {
        vm.prank(owner);
        vm.expectRevert(ParameterRegistry.ZeroAddress.selector);
        new ParameterRegistry(owner, address(0));
    }

    function test_SetUpdater_OnlyOwner() public {
        address newUpdater = makeAddr("newUpdater");

        vm.prank(owner);
        registry.setUpdater(newUpdater);
        assertEq(registry.updater(), newUpdater);

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        registry.setUpdater(makeAddr("anotherUpdater"));
    }

    function test_SetParametersForAsset_OnlyUpdater() public {
        vm.prank(updater);
        registry.setParametersForAsset(
            asset1, "Asset One", address(mockOracleProxy), 1000, 250, 200, 200, 10, true, true, true
        );

        assertTrue(registry.assetExists(asset1));
        assertEq(registry.getAssetName(asset1), "Asset One");
        assertEq(registry.getOracle(asset1), address(mockOracleProxy));

        (
            uint256 maxApy,
            uint256 upperTol,
            uint256 lowerTol,
            uint256 maxDiscount,
            uint80 lookbackWindow,
            bool upperEnabled,
            bool lowerEnabled,
            bool actionEnabled
        ) = registry.getParametersForAsset(asset1);

        assertEq(maxApy, 1000);
        assertEq(upperTol, 250);
        assertEq(lowerTol, 200);
        assertEq(maxDiscount, 200);
        assertEq(lookbackWindow, 10);
        assertTrue(upperEnabled);
        assertTrue(lowerEnabled);
        assertTrue(actionEnabled);
    }

    function test_SetParametersForAsset_RevertsIfNotUpdater() public {
        vm.prank(nonUpdater);
        vm.expectRevert(ParameterRegistry.OnlyUpdater.selector);
        registry.setParametersForAsset(
            asset1, "Asset One", address(mockOracleProxy), 1000, 250, 200, 200, 10, true, true, true
        );
    }

    function test_SetParametersForAsset_RevertsIfZeroOracle() public {
        vm.prank(updater);
        vm.expectRevert(ParameterRegistry.ZeroAddress.selector);
        registry.setParametersForAsset(asset1, "Asset One", address(0), 1000, 250, 200, 200, 10, true, true, true);
    }

    function test_SetIndividualParameters() public {
        vm.prank(updater);
        registry.setParametersForAsset(
            asset1, "Asset One", address(mockOracleProxy), 1000, 250, 200, 200, 10, true, true, true
        );

        vm.prank(updater);
        registry.setMaxExpectedApy(asset1, 2000);

        (uint256 maxApy,,,,,,,) = registry.getParametersForAsset(asset1);
        assertEq(maxApy, 2000);

        vm.prank(updater);
        registry.setUpperBoundTolerance(asset1, 240);

        (, uint256 upperTol,,,,,,) = registry.getParametersForAsset(asset1);
        assertEq(upperTol, 240);

        vm.prank(updater);
        registry.setLowerBoundTolerance(asset1, 220);

        (,, uint256 lowerTol,,,,,) = registry.getParametersForAsset(asset1);
        assertEq(lowerTol, 220);

        vm.prank(updater);
        registry.setMaxDiscount(asset1, 150);

        (,,, uint256 maxDiscount,,,,) = registry.getParametersForAsset(asset1);
        assertEq(maxDiscount, 150);

        vm.prank(updater);
        registry.setLookbackWindowSize(asset1, 20);

        (,,,, uint80 lookbackWindow,,,) = registry.getParametersForAsset(asset1);
        assertEq(lookbackWindow, 20);

        vm.prank(updater);
        registry.setIsUpperBoundEnabled(asset1, false);

        (,,,,, bool upperEnabled,,) = registry.getParametersForAsset(asset1);
        assertFalse(upperEnabled);

        vm.prank(updater);
        registry.setIsLowerBoundEnabled(asset1, false);

        (,,,,,, bool lowerEnabled,) = registry.getParametersForAsset(asset1);
        assertFalse(lowerEnabled);

        vm.prank(updater);
        registry.setIsActionTakingEnabled(asset1, false);

        (,,,,,,, bool actionEnabled) = registry.getParametersForAsset(asset1);
        assertFalse(actionEnabled);
    }

    function test_SetIndividualParameters_RevertsIfAssetNotFound() public {
        vm.prank(updater);
        vm.expectRevert(ParameterRegistry.AssetNotFound.selector);
        registry.setMaxExpectedApy(asset1, 2000);

        vm.prank(updater);
        vm.expectRevert(ParameterRegistry.AssetNotFound.selector);
        registry.setMaxDiscount(asset1, 150);
    }

    function test_SetUpperBoundTolerance_RevertsIfExceedsLimit() public {
        // First create an asset
        vm.prank(updater);
        registry.setParametersForAsset(
            asset1, "Asset One", address(mockOracleProxy), 1000, 100, 100, 100, 10, true, true, true
        );

        // Test that 250 BPS (2.5%) is accepted
        vm.prank(updater);
        registry.setUpperBoundTolerance(asset1, 250);
        (, uint256 upperTol,,,,,,) = registry.getParametersForAsset(asset1);
        assertEq(upperTol, 250);

        // Test that 251 BPS is rejected
        vm.prank(updater);
        vm.expectRevert(abi.encodeWithSelector(ParameterRegistry.UpperBoundToleranceTooHigh.selector, 251));
        registry.setUpperBoundTolerance(asset1, 251);

        // Test that much higher values are rejected
        vm.prank(updater);
        vm.expectRevert(abi.encodeWithSelector(ParameterRegistry.UpperBoundToleranceTooHigh.selector, 1000));
        registry.setUpperBoundTolerance(asset1, 1000);
    }

    function test_SetLowerBoundTolerance_RevertsIfExceedsLimit() public {
        // First create an asset
        vm.prank(updater);
        registry.setParametersForAsset(
            asset1, "Asset One", address(mockOracleProxy), 1000, 100, 100, 100, 10, true, true, true
        );

        // Test that 250 BPS (2.5%) is accepted
        vm.prank(updater);
        registry.setLowerBoundTolerance(asset1, 250);
        (,, uint256 lowerTol,,,,,) = registry.getParametersForAsset(asset1);
        assertEq(lowerTol, 250);

        // Test that 251 BPS is rejected
        vm.prank(updater);
        vm.expectRevert(abi.encodeWithSelector(ParameterRegistry.LowerBoundToleranceTooHigh.selector, 251));
        registry.setLowerBoundTolerance(asset1, 251);

        // Test that much higher values are rejected
        vm.prank(updater);
        vm.expectRevert(abi.encodeWithSelector(ParameterRegistry.LowerBoundToleranceTooHigh.selector, 500));
        registry.setLowerBoundTolerance(asset1, 500);
    }

    function test_SetMaxDiscount_RevertsIfExceedsLimit() public {
        // First create an asset
        vm.prank(updater);
        registry.setParametersForAsset(
            asset1, "Asset One", address(mockOracleProxy), 1000, 100, 100, 100, 10, true, true, true
        );

        // Test that 250 BPS (2.5%) is accepted
        vm.prank(updater);
        registry.setMaxDiscount(asset1, 250);
        (,,, uint256 maxDiscount,,,,) = registry.getParametersForAsset(asset1);
        assertEq(maxDiscount, 250);

        // Test that 251 BPS is rejected
        vm.prank(updater);
        vm.expectRevert(abi.encodeWithSelector(ParameterRegistry.MaxDiscountTooHigh.selector, 251));
        registry.setMaxDiscount(asset1, 251);

        // Test that much higher values are rejected
        vm.prank(updater);
        vm.expectRevert(abi.encodeWithSelector(ParameterRegistry.MaxDiscountTooHigh.selector, 10_000));
        registry.setMaxDiscount(asset1, 10_000);
    }

    function test_SetParametersForAsset_RevertsIfUpperBoundToleranceExceedsLimit() public {
        // Test that 251 BPS upper bound tolerance is rejected during asset creation
        vm.prank(updater);
        vm.expectRevert(abi.encodeWithSelector(ParameterRegistry.UpperBoundToleranceTooHigh.selector, 251));
        registry.setParametersForAsset(
            asset1, "Asset One", address(mockOracleProxy), 1000, 251, 100, 100, 10, true, true, true
        );

        // Test that 250 BPS is accepted
        vm.prank(updater);
        registry.setParametersForAsset(
            asset1, "Asset One", address(mockOracleProxy), 1000, 250, 100, 100, 10, true, true, true
        );
        assertTrue(registry.assetExists(asset1));
    }

    function test_SetParametersForAsset_RevertsIfLowerBoundToleranceExceedsLimit() public {
        // Test that 251 BPS lower bound tolerance is rejected during asset creation
        vm.prank(updater);
        vm.expectRevert(abi.encodeWithSelector(ParameterRegistry.LowerBoundToleranceTooHigh.selector, 251));
        registry.setParametersForAsset(
            asset1, "Asset One", address(mockOracleProxy), 1000, 100, 251, 100, 10, true, true, true
        );

        // Test that 250 BPS is accepted
        vm.prank(updater);
        registry.setParametersForAsset(
            asset1, "Asset One", address(mockOracleProxy), 1000, 100, 250, 100, 10, true, true, true
        );
        assertTrue(registry.assetExists(asset1));
    }

    function test_SetParametersForAsset_RevertsIfMaxDiscountExceedsLimit() public {
        // Test that 251 BPS max discount is rejected during asset creation
        vm.prank(updater);
        vm.expectRevert(abi.encodeWithSelector(ParameterRegistry.MaxDiscountTooHigh.selector, 251));
        registry.setParametersForAsset(
            asset1, "Asset One", address(mockOracleProxy), 1000, 100, 100, 251, 10, true, true, true
        );

        // Test that 250 BPS is accepted
        vm.prank(updater);
        registry.setParametersForAsset(
            asset1, "Asset One", address(mockOracleProxy), 1000, 100, 100, 250, 10, true, true, true
        );
        assertTrue(registry.assetExists(asset1));
    }

    function test_SetParametersForAsset_AllLimitsAtMaximum() public {
        // Test that all parameters can be set to their maximum allowed values
        vm.prank(updater);
        registry.setParametersForAsset(
            asset1, "Asset One", address(mockOracleProxy), 19_999, 250, 250, 250, 10, true, true, true
        );

        (
            uint256 maxApy,
            uint256 upperTol,
            uint256 lowerTol,
            uint256 maxDiscount,
            uint80 lookbackWindow,
            bool upperEnabled,
            bool lowerEnabled,
            bool actionEnabled
        ) = registry.getParametersForAsset(asset1);

        assertEq(maxApy, 19_999);
        assertEq(upperTol, 250);
        assertEq(lowerTol, 250);
        assertEq(maxDiscount, 250);
        assertEq(lookbackWindow, 10);
        assertTrue(upperEnabled);
        assertTrue(lowerEnabled);
        assertTrue(actionEnabled);
    }

    function test_DeleteAsset() public {
        vm.prank(updater);
        registry.setParametersForAsset(
            asset1, "Asset One", address(mockOracleProxy), 1000, 250, 200, 200, 10, true, true, true
        );

        assertTrue(registry.assetExists(asset1));

        vm.prank(updater);
        registry.deleteAsset(asset1);

        assertFalse(registry.assetExists(asset1));

        vm.expectRevert(ParameterRegistry.AssetNotFound.selector);
        registry.getParametersForAsset(asset1);
    }

    function test_DeleteAsset_RevertsIfNotUpdater() public {
        vm.prank(updater);
        registry.setParametersForAsset(
            asset1, "Asset One", address(mockOracleProxy), 1000, 250, 200, 200, 10, true, true, true
        );

        vm.prank(nonUpdater);
        vm.expectRevert(ParameterRegistry.OnlyUpdater.selector);
        registry.deleteAsset(asset1);
    }

    function test_DeleteAsset_RevertsIfAssetNotFound() public {
        vm.prank(updater);
        vm.expectRevert(ParameterRegistry.AssetNotFound.selector);
        registry.deleteAsset(asset1);
    }

    function test_GetParametersForAsset_RevertsIfAssetNotFound() public {
        vm.expectRevert(ParameterRegistry.AssetNotFound.selector);
        registry.getParametersForAsset(asset1);
    }

    function test_GetAssetName_RevertsIfAssetNotFound() public {
        vm.expectRevert(ParameterRegistry.AssetNotFound.selector);
        registry.getAssetName(asset1);
    }

    function test_MultipleAssets() public {
        vm.startPrank(updater);

        registry.setParametersForAsset(
            asset1, "Asset One", address(mockOracleProxy), 1000, 250, 200, 200, 10, true, true, true
        );

        registry.setParametersForAsset(
            asset2, "Asset Two", address(mockOracleProxy), 2000, 240, 230, 250, 20, false, true, false
        );

        vm.stopPrank();

        assertTrue(registry.assetExists(asset1));
        assertTrue(registry.assetExists(asset2));

        assertEq(registry.getAssetName(asset1), "Asset One");
        assertEq(registry.getAssetName(asset2), "Asset Two");

        (uint256 maxApy1,,,,,,,) = registry.getParametersForAsset(asset1);
        (uint256 maxApy2,,,,,,,) = registry.getParametersForAsset(asset2);

        assertEq(maxApy1, 1000);
        assertEq(maxApy2, 2000);
    }

    function test_OwnershipTransfer() public {
        address newOwner = makeAddr("newOwner");

        // Step 1: Current owner initiates transfer
        vm.prank(owner);
        registry.transferOwnership(newOwner);

        // Owner should still be the original owner
        assertEq(registry.owner(), owner);

        // Check that pending owner is set
        assertEq(registry.pendingOwner(), newOwner);

        // Step 2: New owner accepts ownership
        vm.prank(newOwner);
        registry.acceptOwnership();

        // Now ownership should be transferred
        assertEq(registry.owner(), newOwner);
        assertEq(registry.pendingOwner(), address(0));

        // Verify new owner can perform owner actions
        address newerUpdater = makeAddr("newerUpdater");
        vm.prank(newOwner);
        registry.setUpdater(newerUpdater);
        assertEq(registry.updater(), newerUpdater);
    }

    function test_RenounceOwnership() public {
        vm.prank(owner);
        registry.renounceOwnership();

        assertEq(registry.owner(), address(0));

        address newUpdater = makeAddr("newUpdater");
        vm.expectRevert();
        registry.setUpdater(newUpdater);
    }

    function test_AcceptOwnership_RevertsIfNotPendingOwner() public {
        address newOwner = makeAddr("newOwner");
        address randomUser = makeAddr("randomUser");

        // Step 1: Current owner initiates transfer
        vm.prank(owner);
        registry.transferOwnership(newOwner);

        // Step 2: Random user tries to accept ownership
        vm.prank(randomUser);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, randomUser));
        registry.acceptOwnership();
    }

    function test_TransferOwnership_CanBeCancelled() public {
        address newOwner = makeAddr("newOwner");

        // Step 1: Current owner initiates transfer
        vm.prank(owner);
        registry.transferOwnership(newOwner);
        assertEq(registry.pendingOwner(), newOwner);

        // Step 2: Current owner cancels by transferring to address(0)
        vm.prank(owner);
        registry.transferOwnership(address(0));
        assertEq(registry.pendingOwner(), address(0));

        // Step 3: Original new owner can't accept anymore
        vm.prank(newOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, newOwner));
        registry.acceptOwnership();
    }

    function test_TransferOwnership_CanBeChangedBeforeAcceptance() public {
        address newOwner1 = makeAddr("newOwner1");
        address newOwner2 = makeAddr("newOwner2");

        // Step 1: Current owner initiates transfer to newOwner1
        vm.prank(owner);
        registry.transferOwnership(newOwner1);
        assertEq(registry.pendingOwner(), newOwner1);

        // Step 2: Current owner changes to newOwner2
        vm.prank(owner);
        registry.transferOwnership(newOwner2);
        assertEq(registry.pendingOwner(), newOwner2);

        // Step 3: newOwner1 can't accept anymore
        vm.prank(newOwner1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, newOwner1));
        registry.acceptOwnership();

        // Step 4: newOwner2 can accept
        vm.prank(newOwner2);
        registry.acceptOwnership();
        assertEq(registry.owner(), newOwner2);
        assertEq(registry.pendingOwner(), address(0));
    }

    function test_SetOracle() public {
        vm.prank(updater);
        registry.setParametersForAsset(
            asset1, "Asset One", address(mockOracleProxy), 1000, 250, 200, 200, 10, true, true, true
        );

        MockAggregatorV3 newAggregator = new MockAggregatorV3();
        MockOracleProxy newOracleProxy = new MockOracleProxy(address(newAggregator));

        vm.prank(updater);
        registry.setOracle(asset1, address(newOracleProxy));

        assertEq(registry.getOracle(asset1), address(newOracleProxy));
    }

    function test_SetOracle_RevertsIfAssetNotFound() public {
        vm.prank(updater);
        vm.expectRevert(ParameterRegistry.AssetNotFound.selector);
        registry.setOracle(asset1, address(mockOracleProxy));
    }

    function test_SetOracle_RevertsIfZeroAddress() public {
        vm.prank(updater);
        registry.setParametersForAsset(
            asset1, "Asset One", address(mockOracleProxy), 1000, 250, 200, 200, 10, true, true, true
        );

        vm.prank(updater);
        vm.expectRevert(ParameterRegistry.ZeroAddress.selector);
        registry.setOracle(asset1, address(0));
    }

    function test_GetLookbackData() public {
        vm.prank(updater);
        registry.setParametersForAsset(
            asset1, "Asset One", address(mockOracleProxy), 1000, 250, 200, 200, 10, true, true, true
        );

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            registry.getLookbackData(asset1);

        // Latest round is 100, lookback window is 10, so we should get round 90
        assertEq(roundId, 90);
        assertEq(answer, int256(90 * 1e8));
        assertEq(answeredInRound, 90);
        assertTrue(startedAt > 0);
        assertTrue(updatedAt > 0);
    }

    function test_GetLookbackData_RevertsIfAssetNotFound() public {
        vm.expectRevert(ParameterRegistry.AssetNotFound.selector);
        registry.getLookbackData(asset1);
    }

    function test_GetLookbackData_RevertsIfInvalidLookbackWindow() public {
        vm.prank(updater);
        registry.setParametersForAsset(
            asset1, "Asset One", address(mockOracleProxy), 1000, 250, 200, 200, 0, true, true, true
        );

        vm.expectRevert(ParameterRegistry.InvalidLookbackWindow.selector);
        registry.getLookbackData(asset1);
    }

    function test_GetLookbackData_SuccessWithZeroRoundId() public {
        vm.prank(updater);
        registry.setParametersForAsset(
            asset1, "Asset One", address(mockOracleProxyWithZeroRoundId), 1000, 250, 200, 200, 7, true, true, true
        );

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            registry.getLookbackData(asset1);

        assertEq(roundId, 0);
        assertEq(answer, int256(1 * 1e8));
        assertEq(answeredInRound, 0);
        assertTrue(startedAt > 0);
        assertTrue(updatedAt > 0);
    }

    function test_GetLookbackData_SuccessInitiation() public {
        vm.prank(updater);
        registry.setParametersForAsset(
            asset1, "Asset One", address(mockOracleProxy), 1000, 250, 200, 200, 1, true, true, true
        );

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            registry.getLookbackData(asset1);

        assertEq(roundId, 99);
        assertEq(answer, int256(99 * 1e8));
        assertEq(answeredInRound, 99);
        assertTrue(startedAt > 0);
        assertTrue(updatedAt > 0);
    }
}
