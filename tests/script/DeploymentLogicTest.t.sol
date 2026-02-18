// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { DeploymentTestBase } from "./DeploymentTestBase.sol";
import { ParameterRegistry } from "../../src/ParameterRegistry.sol";
import { DeployStructs } from "../../script/config/DeployStructs.sol";

/// @title DeploymentLogicTest
/// @notice Tests the deployment logic without broadcast functionality
contract DeploymentLogicTest is DeploymentTestBase {
    function test_DeployRegistry_Success() public {
        vm.startPrank(deployer);
        ParameterRegistry registry = new ParameterRegistry(deployer, deployer);

        assertEq(registry.owner(), deployer);
        assertEq(registry.updater(), deployer);
        vm.stopPrank();
    }

    function test_ConfigureMainnetAssets() public {
        vm.chainId(1);

        ParameterRegistry registry = deployRegistry(deployer, deployer);
        DeployStructs.AssetConfig[] memory assets = mainnetConfig.getAllAssetConfigs();

        configureAssets(registry, assets);

        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i].oracle != address(0)) {
                assertTrue(registry.assetExists(assets[i].assetAddress));
                assertEq(registry.getAssetName(assets[i].assetAddress), assets[i].assetName);
                assertEq(registry.getOracle(assets[i].assetAddress), assets[i].oracle);
            }
        }
    }

    function test_ConfigureSepoliaAssets() public {
        vm.chainId(11_155_111);

        ParameterRegistry registry = deployRegistry(deployer, deployer);
        DeployStructs.AssetConfig[] memory assets = sepoliaConfig.getAllAssetConfigs();

        // Sepolia assets have oracle = address(0) by default (set after deployment)
        // So just verify the config loads without errors
        assertEq(assets.length, 2, "Sepolia should have 2 assets");
    }

    function test_ConfigureAnvilAssets() public {
        vm.chainId(31_337);

        ParameterRegistry registry = deployRegistry(deployer, deployer);
        DeployStructs.AssetConfig[] memory assets = anvilConfig.getAllAssetConfigs();

        assertEq(assets.length, 3, "Anvil should have 3 mock assets");

        configureAssets(registry, assets);

        for (uint256 i = 0; i < assets.length; i++) {
            assertTrue(registry.assetExists(assets[i].assetAddress));
            assertEq(registry.getAssetName(assets[i].assetAddress), assets[i].assetName);
        }
    }

    function test_TransferRoles_Success() public {
        ParameterRegistry registry = deployRegistry(deployer, deployer);

        transferRoles(registry, pendingUpdater, pendingOwner);

        assertEq(registry.updater(), pendingUpdater);
        assertEq(registry.pendingOwner(), pendingOwner);
        assertEq(registry.owner(), deployer); // Still deployer until accepted
    }

    function test_AcceptOwnership_Success() public {
        ParameterRegistry registry = deployRegistry(deployer, deployer);

        vm.prank(deployer);
        registry.transferOwnership(pendingOwner);

        vm.prank(pendingOwner);
        registry.acceptOwnership();

        assertEq(registry.owner(), pendingOwner);
        assertEq(registry.pendingOwner(), address(0));
    }

    function test_RoleTransfer_RequiresOwner() public {
        ParameterRegistry registry = deployRegistry(deployer, deployer);

        vm.startPrank(pendingOwner); // Not the owner

        vm.expectRevert();
        registry.setUpdater(pendingUpdater);

        vm.expectRevert();
        registry.transferOwnership(pendingOwner);

        vm.stopPrank();
    }

    function test_AssetConfiguration_RequiresUpdater() public {
        ParameterRegistry registry = deployRegistry(deployer, deployer);

        vm.prank(deployer);
        registry.setUpdater(pendingUpdater);

        vm.startPrank(deployer); // No longer updater

        vm.expectRevert();
        registry.setParametersForAsset(
            makeAddr("asset"), "Test Asset", makeAddr("oracle"), 500, 100, 100, 200, 24, true, true, false
        );

        vm.stopPrank();
    }

    function test_DeleteAsset_Success() public {
        ParameterRegistry registry = deployRegistry(deployer, deployer);

        address assetAddress = makeAddr("testAsset");

        vm.startPrank(deployer);
        registry.setParametersForAsset(
            assetAddress, "Test Asset", makeAddr("oracle"), 500, 100, 100, 200, 24, true, true, false
        );

        assertTrue(registry.assetExists(assetAddress));

        registry.deleteAsset(assetAddress);

        assertFalse(registry.assetExists(assetAddress));

        vm.stopPrank();
    }

    function test_ParameterLimits() public {
        ParameterRegistry registry = deployRegistry(deployer, deployer);

        vm.startPrank(deployer);

        // Test maximum allowed values
        registry.setParametersForAsset(
            makeAddr("maxAsset"), "Max Asset", makeAddr("oracle"), 10_000, 250, 250, 250, 1000, true, true, true
        );

        // Test exceeding upper bound tolerance limit
        vm.expectRevert();
        registry.setParametersForAsset(
            makeAddr("exceedAsset"),
            "Exceed Asset",
            makeAddr("oracle"),
            500,
            251, // Exceeds max upper bound tolerance
            100,
            100,
            24,
            true,
            true,
            false
        );

        vm.stopPrank();
    }
}
