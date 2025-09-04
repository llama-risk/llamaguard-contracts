// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29 <0.9.0;

import { Test } from "forge-std/src/Test.sol";
import { ParameterRegistry } from "../src/ParameterRegistry.sol";
import { MockAggregatorV3 } from "./mocks/MockAggregatorV3.sol";

contract ParameterRegistryTest is Test {
    ParameterRegistry internal registry;
    MockAggregatorV3 internal oracle1;
    MockAggregatorV3 internal oracle2;
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

        // Deploy mock oracles
        oracle1 = new MockAggregatorV3(8, "ETH / USD");
        oracle2 = new MockAggregatorV3(8, "BTC / USD");
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
        vm.expectRevert();
        registry.setUpdater(makeAddr("anotherUpdater"));
    }

    function test_SetParametersForAsset_OnlyUpdater() public {
        vm.prank(updater);
        registry.setParametersForAsset(asset1, "Asset One", address(oracle1), 1000, 500, 300, 5, true, true, true);

        assertTrue(registry.assetExists(asset1));
        assertEq(registry.getAssetName(asset1), "Asset One");
        assertEq(registry.getAssetOracle(asset1), address(oracle1));

        (
            uint256 maxApy,
            uint256 upperTol,
            uint256 lowerTol,
            uint256 window,
            bool upperEnabled,
            bool lowerEnabled,
            bool actionEnabled
        ) = registry.getParametersForAsset(asset1);

        assertEq(maxApy, 1000);
        assertEq(upperTol, 500);
        assertEq(lowerTol, 300);
        assertEq(window, 5);
        assertTrue(upperEnabled);
        assertTrue(lowerEnabled);
        assertTrue(actionEnabled);
    }

    function test_SetParametersForAsset_RevertsIfNotUpdater() public {
        vm.prank(nonUpdater);
        vm.expectRevert(ParameterRegistry.OnlyUpdater.selector);
        registry.setParametersForAsset(asset1, "Asset One", address(oracle1), 1000, 500, 300, 5, true, true, true);
    }

    function test_SetIndividualParameters() public {
        vm.prank(updater);
        registry.setParametersForAsset(asset1, "Asset One", address(oracle1), 1000, 500, 300, 5, true, true, true);

        vm.prank(updater);
        registry.setMaxExpectedApy(asset1, 2000);

        (uint256 maxApy,,,,,,) = registry.getParametersForAsset(asset1);
        assertEq(maxApy, 2000);

        vm.prank(updater);
        registry.setUpperBoundTolerance(asset1, 600);

        (, uint256 upperTol,,,,,) = registry.getParametersForAsset(asset1);
        assertEq(upperTol, 600);

        vm.prank(updater);
        registry.setLowerBoundTolerance(asset1, 400);

        (,, uint256 lowerTol,,,,) = registry.getParametersForAsset(asset1);
        assertEq(lowerTol, 400);

        vm.prank(updater);
        registry.setWindow(asset1, 10);

        (,,, uint256 window,,,) = registry.getParametersForAsset(asset1);
        assertEq(window, 10);

        vm.prank(updater);
        registry.setIsUpperBoundEnabled(asset1, false);

        (,,,, bool upperEnabled,,) = registry.getParametersForAsset(asset1);
        assertFalse(upperEnabled);

        vm.prank(updater);
        registry.setIsLowerBoundEnabled(asset1, false);

        (,,,,, bool lowerEnabled,) = registry.getParametersForAsset(asset1);
        assertFalse(lowerEnabled);

        vm.prank(updater);
        registry.setIsActionTakingEnabled(asset1, false);

        (,,,,,, bool actionEnabled) = registry.getParametersForAsset(asset1);
        assertFalse(actionEnabled);

        vm.prank(updater);
        registry.setOracle(asset1, address(oracle2));
        assertEq(registry.getAssetOracle(asset1), address(oracle2));
    }

    function test_SetIndividualParameters_RevertsIfAssetNotFound() public {
        vm.prank(updater);
        vm.expectRevert(ParameterRegistry.AssetNotFound.selector);
        registry.setMaxExpectedApy(asset1, 2000);
    }

    function test_DeleteAsset() public {
        vm.prank(updater);
        registry.setParametersForAsset(asset1, "Asset One", address(oracle1), 1000, 500, 300, 5, true, true, true);

        assertTrue(registry.assetExists(asset1));

        vm.prank(updater);
        registry.deleteAsset(asset1);

        assertFalse(registry.assetExists(asset1));

        vm.expectRevert(ParameterRegistry.AssetNotFound.selector);
        registry.getParametersForAsset(asset1);
    }

    function test_DeleteAsset_RevertsIfNotUpdater() public {
        vm.prank(updater);
        registry.setParametersForAsset(asset1, "Asset One", address(oracle1), 1000, 500, 300, 5, true, true, true);

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

        registry.setParametersForAsset(asset1, "Asset One", address(oracle1), 1000, 500, 300, 5, true, true, true);

        registry.setParametersForAsset(asset2, "Asset Two", address(oracle2), 2000, 600, 400, 3, false, true, false);

        vm.stopPrank();

        assertTrue(registry.assetExists(asset1));
        assertTrue(registry.assetExists(asset2));

        assertEq(registry.getAssetName(asset1), "Asset One");
        assertEq(registry.getAssetName(asset2), "Asset Two");

        (uint256 maxApy1,,,,,,) = registry.getParametersForAsset(asset1);
        (uint256 maxApy2,,,,,,) = registry.getParametersForAsset(asset2);

        assertEq(maxApy1, 1000);
        assertEq(maxApy2, 2000);
    }

    function test_OwnershipTransfer() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        registry.transferOwnership(newOwner);

        assertEq(registry.owner(), newOwner);

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

    function test_GetRoundDatas_Success() public {
        // Setup oracle with multiple rounds
        uint80[] memory roundIds = new uint80[](10);
        int256[] memory answers = new int256[](10);
        uint256[] memory timestamps = new uint256[](10);

        for (uint80 i = 0; i < 10; i++) {
            roundIds[i] = i + 1;
            answers[i] = int256(uint256(2000 + i * 10)) * 1e8; // Prices from 2000 to 2090
            timestamps[i] = block.timestamp - (9 - i) * 3600; // 1 hour apart
        }

        oracle1.setMultipleRounds(roundIds, answers, timestamps);

        // Setup asset with window of 5
        vm.prank(updater);
        registry.setParametersForAsset(asset1, "Asset One", address(oracle1), 1000, 500, 300, 5, true, true, true);

        // Get round datas
        (int256[] memory returnedAnswers, uint256[] memory returnedTimestamps) = registry.getRoundDatas(asset1);

        // Should return 6 values (current + 5 historical)
        assertEq(returnedAnswers.length, 6);
        assertEq(returnedTimestamps.length, 6);

        // Check latest value
        assertEq(returnedAnswers[0], int256(uint256(2090)) * 1e8);
        assertEq(returnedTimestamps[0], timestamps[9]);

        // Check historical values
        for (uint256 i = 1; i <= 5; i++) {
            assertEq(returnedAnswers[i], answers[10 - i - 1]);
            assertEq(returnedTimestamps[i], timestamps[10 - i - 1]);
        }
    }

    function test_GetRoundDatas_HandlesLimitedHistory() public {
        // Setup oracle with only 3 rounds
        uint80[] memory roundIds = new uint80[](3);
        int256[] memory answers = new int256[](3);
        uint256[] memory timestamps = new uint256[](3);

        for (uint80 i = 0; i < 3; i++) {
            roundIds[i] = i + 1;
            answers[i] = int256(uint256(2000 + i * 10)) * 1e8;
            timestamps[i] = block.timestamp - (2 - i) * 3600;
        }

        oracle1.setMultipleRounds(roundIds, answers, timestamps);

        // Setup asset with window of 10 (more than available history)
        vm.prank(updater);
        registry.setParametersForAsset(asset1, "Asset One", address(oracle1), 1000, 500, 300, 10, true, true, true);

        // Get round datas
        (int256[] memory returnedAnswers, uint256[] memory returnedTimestamps) = registry.getRoundDatas(asset1);

        // Should return only 3 values (all available history)
        assertEq(returnedAnswers.length, 3);
        assertEq(returnedTimestamps.length, 3);

        // Check all values
        for (uint256 i = 0; i < 3; i++) {
            assertEq(returnedAnswers[i], answers[3 - i - 1]);
            assertEq(returnedTimestamps[i], timestamps[3 - i - 1]);
        }
    }

    function test_GetRoundDatas_RevertsIfAssetNotFound() public {
        vm.expectRevert(ParameterRegistry.AssetNotFound.selector);
        registry.getRoundDatas(asset1);
    }

    function test_GetRoundDatas_RevertsIfOracleNotSet() public {
        // Setup asset without oracle (using zero address)
        vm.prank(updater);
        vm.expectRevert(ParameterRegistry.ZeroAddress.selector);
        registry.setParametersForAsset(asset1, "Asset One", address(0), 1000, 500, 300, 5, true, true, true);
    }

    function test_GetRoundDatas_WindowZero() public {
        // Setup oracle with rounds
        uint80[] memory roundIds = new uint80[](5);
        int256[] memory answers = new int256[](5);
        uint256[] memory timestamps = new uint256[](5);

        for (uint80 i = 0; i < 5; i++) {
            roundIds[i] = i + 1;
            answers[i] = int256(uint256(2000 + i * 10)) * 1e8;
            timestamps[i] = block.timestamp - (4 - i) * 3600;
        }

        oracle1.setMultipleRounds(roundIds, answers, timestamps);

        // Setup asset with window of 0
        vm.prank(updater);
        registry.setParametersForAsset(asset1, "Asset One", address(oracle1), 1000, 500, 300, 0, true, true, true);

        // Get round datas
        (int256[] memory returnedAnswers, uint256[] memory returnedTimestamps) = registry.getRoundDatas(asset1);

        // Should return only 1 value (latest)
        assertEq(returnedAnswers.length, 1);
        assertEq(returnedTimestamps.length, 1);
        assertEq(returnedAnswers[0], answers[4]);
        assertEq(returnedTimestamps[0], timestamps[4]);
    }

    function test_SetOracle_RevertsIfAssetNotFound() public {
        vm.prank(updater);
        vm.expectRevert(ParameterRegistry.AssetNotFound.selector);
        registry.setOracle(asset1, address(oracle1));
    }

    function test_SetOracle_RevertsIfZeroAddress() public {
        vm.prank(updater);
        registry.setParametersForAsset(asset1, "Asset One", address(oracle1), 1000, 500, 300, 5, true, true, true);

        vm.prank(updater);
        vm.expectRevert(ParameterRegistry.ZeroAddress.selector);
        registry.setOracle(asset1, address(0));
    }

    function test_SetWindow_RevertsIfAssetNotFound() public {
        vm.prank(updater);
        vm.expectRevert(ParameterRegistry.AssetNotFound.selector);
        registry.setWindow(asset1, 10);
    }
}
