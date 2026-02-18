// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { Test } from "forge-std/Test.sol";
import { ParameterRegistry } from "../../src/ParameterRegistry.sol";
import { DeployParameterRegistry } from "../../script/parameter-registry/DeployParameterRegistry.s.sol";
import { DeployStructs } from "../../script/config/DeployStructs.sol";
import { MainnetConfig } from "../../script/config/MainnetConfig.sol";
import { AnvilConfig } from "../../script/config/AnvilConfig.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title ParameterRegistryDeploymentTest
/// @notice Test suite for ParameterRegistry deployment
contract ParameterRegistryDeploymentTest is Test {
    DeployParameterRegistry internal deployScript;
    MainnetConfig internal mainnetConfig;
    AnvilConfig internal anvilConfig;

    address internal deployer;
    address internal pendingOwner;
    address internal pendingUpdater;
    address internal unauthorizedUser;

    function setUp() public {
        vm.setEnv("ETH_FROM", "0x0000000000000000000000000000000000000aBc");
        deployer = address(0x0000000000000000000000000000000000000aBc);

        pendingOwner = makeAddr("pendingOwner");
        pendingUpdater = makeAddr("pendingUpdater");
        unauthorizedUser = makeAddr("unauthorizedUser");

        deployScript = new DeployParameterRegistry();
        mainnetConfig = new MainnetConfig();
        anvilConfig = new AnvilConfig();

        vm.deal(deployer, 10 ether);
    }

    function test_Deploy_Success() public {
        vm.chainId(31_337);

        ParameterRegistry registry = deployScript.run();

        assertNotEq(address(registry), address(0), "Registry should be deployed");
        assertEq(registry.owner(), deployer, "Owner should be deployer");
        assertEq(registry.updater(), deployer, "Updater should be deployer");
    }

    function test_Deploy_ConfigureMainnetAssets() public {
        vm.chainId(1);

        ParameterRegistry registry = deployScript.run();
        DeployStructs.AssetConfig[] memory assets = mainnetConfig.getAllAssetConfigs();

        // Configure assets manually
        vm.startPrank(deployer);
        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i].oracle == address(0)) continue;

            registry.setParametersForAsset(
                assets[i].assetAddress,
                assets[i].assetName,
                assets[i].oracle,
                assets[i].maxExpectedApy,
                assets[i].upperBoundTolerance,
                assets[i].lowerBoundTolerance,
                assets[i].maxDiscount,
                assets[i].lookbackWindowSize,
                assets[i].isUpperBoundEnabled,
                assets[i].isLowerBoundEnabled,
                assets[i].isActionTakingEnabled
            );
        }
        vm.stopPrank();

        // Verify assets
        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i].oracle != address(0)) {
                assertTrue(registry.assetExists(assets[i].assetAddress), "Asset should exist");
                assertEq(registry.getAssetName(assets[i].assetAddress), assets[i].assetName);
            }
        }
    }

    function test_Deploy_ConfigureAnvilAssets() public {
        vm.chainId(31_337);

        ParameterRegistry registry = deployScript.run();
        DeployStructs.AssetConfig[] memory assets = anvilConfig.getAllAssetConfigs();

        assertEq(assets.length, 3, "Anvil should have 3 mock assets");

        vm.startPrank(deployer);
        for (uint256 i = 0; i < assets.length; i++) {
            registry.setParametersForAsset(
                assets[i].assetAddress,
                assets[i].assetName,
                assets[i].oracle,
                assets[i].maxExpectedApy,
                assets[i].upperBoundTolerance,
                assets[i].lowerBoundTolerance,
                assets[i].maxDiscount,
                assets[i].lookbackWindowSize,
                assets[i].isUpperBoundEnabled,
                assets[i].isLowerBoundEnabled,
                assets[i].isActionTakingEnabled
            );
        }
        vm.stopPrank();

        for (uint256 i = 0; i < assets.length; i++) {
            assertTrue(registry.assetExists(assets[i].assetAddress), "Mock asset should exist");
            assertEq(registry.getAssetName(assets[i].assetAddress), assets[i].assetName);
        }
    }

    function test_OwnershipAcceptance_Flow() public {
        vm.chainId(1);

        ParameterRegistry registry = deployScript.run();

        vm.startPrank(deployer);
        registry.transferOwnership(pendingOwner);
        vm.stopPrank();

        assertEq(registry.pendingOwner(), pendingOwner);
        assertEq(registry.owner(), deployer);

        vm.startPrank(pendingOwner);
        registry.acceptOwnership();
        vm.stopPrank();

        assertEq(registry.owner(), pendingOwner);
        assertEq(registry.pendingOwner(), address(0));
    }

    function test_OwnershipTransfer_CanBeCancelled() public {
        vm.chainId(1);
        ParameterRegistry registry = deployScript.run();

        vm.startPrank(deployer);
        registry.transferOwnership(pendingOwner);
        assertEq(registry.pendingOwner(), pendingOwner);

        registry.transferOwnership(address(0));
        assertEq(registry.pendingOwner(), address(0));
        vm.stopPrank();

        vm.startPrank(pendingOwner);
        vm.expectRevert();
        registry.acceptOwnership();
        vm.stopPrank();
    }

    function test_AssetConfiguration_RequiresUpdaterRole() public {
        vm.chainId(1);
        ParameterRegistry registry = deployScript.run();

        vm.startPrank(deployer);
        registry.setUpdater(pendingUpdater);
        vm.stopPrank();

        vm.startPrank(deployer);
        vm.expectRevert(ParameterRegistry.OnlyUpdater.selector);
        registry.setParametersForAsset(
            makeAddr("asset"), "Test Asset", makeAddr("oracle"), 1000, 100, 100, 200, 10, true, true, false
        );
        vm.stopPrank();

        vm.startPrank(pendingUpdater);
        registry.setParametersForAsset(
            makeAddr("asset"), "Test Asset", makeAddr("oracle"), 1000, 100, 100, 200, 10, true, true, false
        );
        assertTrue(registry.assetExists(makeAddr("asset")), "Asset should be configured");
        vm.stopPrank();
    }

    function test_ZeroAddressValidation() public {
        vm.chainId(1);
        ParameterRegistry registry = deployScript.run();

        vm.startPrank(deployer);
        vm.expectRevert(ParameterRegistry.ZeroAddress.selector);
        registry.setUpdater(address(0));

        vm.expectRevert(ParameterRegistry.ZeroAddress.selector);
        registry.setParametersForAsset(
            makeAddr("asset"), "Test Asset", address(0), 1000, 100, 100, 200, 10, true, true, false
        );
        vm.stopPrank();
    }

    function test_ParameterLimitsValidation() public {
        vm.chainId(1);
        ParameterRegistry registry = deployScript.run();

        vm.startPrank(deployer);

        vm.expectRevert(abi.encodeWithSelector(ParameterRegistry.UpperBoundToleranceTooHigh.selector, 251));
        registry.setParametersForAsset(
            makeAddr("asset1"), "Asset 1", makeAddr("oracle1"), 1000, 251, 100, 100, 10, true, true, false
        );

        vm.expectRevert(abi.encodeWithSelector(ParameterRegistry.LowerBoundToleranceTooHigh.selector, 251));
        registry.setParametersForAsset(
            makeAddr("asset2"), "Asset 2", makeAddr("oracle2"), 1000, 100, 251, 100, 10, true, true, false
        );

        vm.expectRevert(abi.encodeWithSelector(ParameterRegistry.MaxDiscountTooHigh.selector, 251));
        registry.setParametersForAsset(
            makeAddr("asset3"), "Asset 3", makeAddr("oracle3"), 1000, 100, 100, 251, 10, true, true, false
        );

        vm.stopPrank();
    }

    function test_AssetDeletion_OnlyUpdater() public {
        vm.chainId(1);
        ParameterRegistry registry = deployScript.run();

        address testAsset = makeAddr("testAsset");

        vm.startPrank(deployer);
        registry.setParametersForAsset(
            testAsset, "Test Asset", makeAddr("oracle"), 1000, 100, 100, 200, 10, true, true, false
        );
        assertTrue(registry.assetExists(testAsset));
        vm.stopPrank();

        vm.startPrank(unauthorizedUser);
        vm.expectRevert(ParameterRegistry.OnlyUpdater.selector);
        registry.deleteAsset(testAsset);
        vm.stopPrank();

        vm.startPrank(deployer);
        registry.deleteAsset(testAsset);
        assertFalse(registry.assetExists(testAsset));
        vm.stopPrank();
    }

    function test_MultipleAssetsConfiguration() public {
        vm.chainId(1);
        ParameterRegistry registry = deployScript.run();

        address[] memory a_ = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            a_[i] = makeAddr(string(abi.encodePacked("asset", i)));
        }

        vm.startPrank(deployer);
        for (uint256 i = 0; i < a_.length; i++) {
            registry.setParametersForAsset(
                a_[i],
                string(abi.encodePacked("Asset ", i)),
                makeAddr(string(abi.encodePacked("oracle", i))),
                1000 + uint64(i * 100),
                100 + uint32(i * 10),
                100 + uint32(i * 5),
                150 + uint32(i * 10),
                10 + uint80(i * 2),
                true,
                i % 2 == 0,
                false
            );
        }

        for (uint256 i = 0; i < a_.length; i++) {
            assertTrue(registry.assetExists(a_[i]));
            assertEq(registry.getAssetName(a_[i]), string(abi.encodePacked("Asset ", i)));
        }
        vm.stopPrank();
    }
}
