// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29 <0.9.0;

import { Test } from "forge-std/src/Test.sol";
import { ParameterRegistry } from "../src/ParameterRegistry.sol";
import { MockAggregatorV3 } from "./mocks/MockAggregatorV3.sol";

contract ParameterRegistryTest is Test {
    ParameterRegistry internal registry;
    MockAggregatorV3 internal mockOracle;
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
        
        // Deploy mock oracle
        mockOracle = new MockAggregatorV3();
        
        // Set up some mock round data
        for (uint80 i = 1; i <= 100; i++) {
            mockOracle.setRoundData(
                i,
                int256(uint256(i) * 1e8), // answer
                block.timestamp - (100 - i) * 3600, // startedAt
                block.timestamp - (100 - i) * 3600, // updatedAt
                i // answeredInRound
            );
        }
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
        registry.setParametersForAsset(asset1, "Asset One", address(mockOracle), 1000, 500, 300, 10, true, true, true);

        assertTrue(registry.assetExists(asset1));
        assertEq(registry.getAssetName(asset1), "Asset One");
        assertEq(registry.getOracle(asset1), address(mockOracle));

        (uint256 maxApy, uint256 upperTol, uint256 lowerTol, uint80 lookbackWindow, bool upperEnabled, bool lowerEnabled, bool actionEnabled) =
            registry.getParametersForAsset(asset1);

        assertEq(maxApy, 1000);
        assertEq(upperTol, 500);
        assertEq(lowerTol, 300);
        assertEq(lookbackWindow, 10);
        assertTrue(upperEnabled);
        assertTrue(lowerEnabled);
        assertTrue(actionEnabled);
    }

    function test_SetParametersForAsset_RevertsIfNotUpdater() public {
        vm.prank(nonUpdater);
        vm.expectRevert(ParameterRegistry.OnlyUpdater.selector);
        registry.setParametersForAsset(asset1, "Asset One", address(mockOracle), 1000, 500, 300, 10, true, true, true);
    }
    
    function test_SetParametersForAsset_RevertsIfZeroOracle() public {
        vm.prank(updater);
        vm.expectRevert(ParameterRegistry.ZeroAddress.selector);
        registry.setParametersForAsset(asset1, "Asset One", address(0), 1000, 500, 300, 10, true, true, true);
    }

    function test_SetIndividualParameters() public {
        vm.prank(updater);
        registry.setParametersForAsset(asset1, "Asset One", address(mockOracle), 1000, 500, 300, 10, true, true, true);

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
        registry.setLookbackWindowSize(asset1, 20);
        
        (,,, uint80 lookbackWindow,,,) = registry.getParametersForAsset(asset1);
        assertEq(lookbackWindow, 20);

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
    }

    function test_SetIndividualParameters_RevertsIfAssetNotFound() public {
        vm.prank(updater);
        vm.expectRevert(ParameterRegistry.AssetNotFound.selector);
        registry.setMaxExpectedApy(asset1, 2000);
    }

    function test_DeleteAsset() public {
        vm.prank(updater);
        registry.setParametersForAsset(asset1, "Asset One", address(mockOracle), 1000, 500, 300, 10, true, true, true);

        assertTrue(registry.assetExists(asset1));

        vm.prank(updater);
        registry.deleteAsset(asset1);

        assertFalse(registry.assetExists(asset1));

        vm.expectRevert(ParameterRegistry.AssetNotFound.selector);
        registry.getParametersForAsset(asset1);
    }

    function test_DeleteAsset_RevertsIfNotUpdater() public {
        vm.prank(updater);
        registry.setParametersForAsset(asset1, "Asset One", address(mockOracle), 1000, 500, 300, 10, true, true, true);

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

        registry.setParametersForAsset(asset1, "Asset One", address(mockOracle), 1000, 500, 300, 10, true, true, true);

        registry.setParametersForAsset(asset2, "Asset Two", address(mockOracle), 2000, 600, 400, 20, false, true, false);

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
    
    function test_SetOracle() public {
        vm.prank(updater);
        registry.setParametersForAsset(asset1, "Asset One", address(mockOracle), 1000, 500, 300, 10, true, true, true);
        
        MockAggregatorV3 newOracle = new MockAggregatorV3();
        
        vm.prank(updater);
        registry.setOracle(asset1, address(newOracle));
        
        assertEq(registry.getOracle(asset1), address(newOracle));
    }
    
    function test_SetOracle_RevertsIfAssetNotFound() public {
        vm.prank(updater);
        vm.expectRevert(ParameterRegistry.AssetNotFound.selector);
        registry.setOracle(asset1, address(mockOracle));
    }
    
    function test_SetOracle_RevertsIfZeroAddress() public {
        vm.prank(updater);
        registry.setParametersForAsset(asset1, "Asset One", address(mockOracle), 1000, 500, 300, 10, true, true, true);
        
        vm.prank(updater);
        vm.expectRevert(ParameterRegistry.ZeroAddress.selector);
        registry.setOracle(asset1, address(0));
    }
    
    function test_GetLookbackData() public {
        vm.prank(updater);
        registry.setParametersForAsset(asset1, "Asset One", address(mockOracle), 1000, 500, 300, 10, true, true, true);
        
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
        registry.setParametersForAsset(asset1, "Asset One", address(mockOracle), 1000, 500, 300, 0, true, true, true);
        
        vm.expectRevert(ParameterRegistry.InvalidLookbackWindow.selector);
        registry.getLookbackData(asset1);
    }
    
    function test_GetLookbackData_SuccessInitiation() public {
        vm.prank(updater);
        registry.setParametersForAsset(asset1, "Asset One", address(mockOracle), 1000, 500, 300, 200, true, true, true);
        
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = 
            registry.getLookbackData(asset1);
        
        assertEq(roundId, 1);
        assertEq(answer, int256(1 * 1e8));
        assertEq(answeredInRound, 1);
        assertTrue(startedAt > 0);
        assertTrue(updatedAt > 0);
    }
}
