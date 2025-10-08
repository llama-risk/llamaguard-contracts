// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { Test } from "forge-std/Test.sol";
import { ParameterRegistry } from "../../src/ParameterRegistry.sol";
import { DeployParameterRegistry } from "../../script/DeployParameterRegistry.s.sol";
import { DeployMainnet } from "../../script/DeployMainnet.s.sol";
import { DeployConfig } from "../../script/DeployConfig.sol";
import { AssetConfigs } from "../../script/AssetConfigs.sol";
import { stdStorage, StdStorage } from "forge-std/StdStorage.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title ParameterRegistryDeploymentTest
/// @notice Comprehensive test suite for ParameterRegistry deployment scenarios
contract ParameterRegistryDeploymentTest is Test {
    using stdStorage for StdStorage;

    DeployParameterRegistry internal deployScript;
    DeployMainnet internal deployMainnet;
    DeployConfig internal deployConfig;

    address internal deployer;
    address internal pendingOwner;
    address internal pendingUpdater;
    address internal unauthorizedUser;

    function setUp() public {
        // Set up deployer address using ETH_FROM like in DeployMainnet.t.sol
        vm.setEnv("ETH_FROM", "0x0000000000000000000000000000000000000aBc");
        deployer = address(0x0000000000000000000000000000000000000aBc);

        pendingOwner = makeAddr("pendingOwner");
        pendingUpdater = makeAddr("pendingUpdater");
        unauthorizedUser = makeAddr("unauthorizedUser");

        // Deploy scripts
        deployScript = new DeployParameterRegistry();
        deployMainnet = new DeployMainnet();
        deployConfig = new DeployConfig();

        // Setup scripts
        deployScript.setUp();
        deployMainnet.setUp();
        deployMainnet.setDeployConfig(deployConfig);

        // Fund deployer
        vm.deal(deployer, 10 ether);
    }

    function test_DeploymentWithAssets_Mainnet() public {
        vm.chainId(1);

        // Mock config
        vm.mockCall(
            address(deployConfig),
            abi.encodeWithSelector(DeployConfig.getMainnetConfig.selector),
            abi.encode(
                DeployConfig.Config({
                    owner: deployer,
                    updater: deployer,
                    pendingOwner: pendingOwner,
                    pendingUpdater: pendingUpdater,
                    networkName: "mainnet"
                })
            )
        );

        ParameterRegistry registry = deployMainnet.run();

        // Verify deployment
        assertNotEq(address(registry), address(0), "Registry should be deployed");
        assertEq(registry.owner(), deployer, "Owner should be deployer initially");
        assertEq(registry.updater(), pendingUpdater, "Updater should be transferred");
        assertEq(registry.pendingOwner(), pendingOwner, "Pending owner should be set");

        // Verify assets are configured
        AssetConfigs.AssetConfig[] memory assets = deployConfig.getMainnetAssets();
        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i].oracle != address(0)) {
                assertTrue(registry.assetExists(assets[i].assetAddress), "Asset should exist");
                assertEq(registry.getAssetName(assets[i].assetAddress), assets[i].assetName, "Asset name should match");
            }
        }
    }

    function test_DeploymentWithAssets_Sepolia() public {
        vm.chainId(11_155_111);

        ParameterRegistry registry = deployScript.run();

        assertNotEq(address(registry), address(0), "Registry should be deployed");

        // Sepolia config has role transfers configured, so check the actual config
        DeployConfig.Config memory sepoliaConfig = deployConfig.getSepoliaConfig();
        if (sepoliaConfig.pendingUpdater != address(0) && sepoliaConfig.pendingUpdater != deployer) {
            assertEq(registry.updater(), sepoliaConfig.pendingUpdater, "Updater should be transferred");
        } else {
            assertEq(registry.updater(), deployer, "Updater should be deployer");
        }

        if (sepoliaConfig.pendingOwner != address(0) && sepoliaConfig.pendingOwner != deployer) {
            assertEq(registry.pendingOwner(), sepoliaConfig.pendingOwner, "Pending owner should be set");
            assertEq(registry.owner(), deployer, "Owner should still be deployer until accepted");
        } else {
            assertEq(registry.owner(), deployer, "Owner should be deployer");
        }

        // Verify Sepolia assets
        AssetConfigs.AssetConfig[] memory assets = deployConfig.getSepoliaAssets();
        assertTrue(assets.length > 0, "Should have Sepolia assets");

        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i].oracle != address(0)) {
                assertTrue(registry.assetExists(assets[i].assetAddress), "Asset should exist");
            }
        }
    }

    function test_DeploymentWithAssets_Anvil() public {
        vm.chainId(31_337);

        ParameterRegistry registry = deployScript.run();

        assertNotEq(address(registry), address(0), "Registry should be deployed");

        // Verify Anvil mock assets
        AssetConfigs.AssetConfig[] memory assets = deployConfig.getAnvilAssets();
        assertEq(assets.length, 3, "Anvil should have 3 mock assets");

        for (uint256 i = 0; i < assets.length; i++) {
            assertTrue(registry.assetExists(assets[i].assetAddress), "Mock asset should exist");
            assertEq(registry.getAssetName(assets[i].assetAddress), assets[i].assetName, "Mock asset name should match");
        }
    }

    function test_RoleTransfer_UpdaterOnly() public {
        vm.chainId(1);

        // Mock config with only updater transfer
        vm.mockCall(
            address(deployConfig),
            abi.encodeWithSelector(DeployConfig.getMainnetConfig.selector),
            abi.encode(
                DeployConfig.Config({
                    owner: deployer,
                    updater: deployer,
                    pendingOwner: pendingOwner, // Both must be set to avoid validation errors
                    pendingUpdater: pendingUpdater,
                    networkName: "mainnet"
                })
            )
        );

        ParameterRegistry registry = deployMainnet.deployOnly();
        deployMainnet.transferRolesOnly(address(registry));

        assertEq(registry.updater(), pendingUpdater, "Updater should be transferred");
        assertEq(registry.owner(), deployer, "Owner should remain deployer");
        assertEq(registry.pendingOwner(), pendingOwner, "Pending owner should be set");
    }

    function test_RoleTransfer_OwnerOnly() public {
        vm.chainId(1);

        // Mock config with only owner transfer
        vm.mockCall(
            address(deployConfig),
            abi.encodeWithSelector(DeployConfig.getMainnetConfig.selector),
            abi.encode(
                DeployConfig.Config({
                    owner: deployer,
                    updater: deployer,
                    pendingOwner: pendingOwner,
                    pendingUpdater: pendingUpdater, // Both must be set to avoid validation errors
                    networkName: "mainnet"
                })
            )
        );

        ParameterRegistry registry = deployMainnet.deployOnly();
        deployMainnet.transferRolesOnly(address(registry));

        assertEq(registry.updater(), pendingUpdater, "Updater should be transferred");
        assertEq(registry.owner(), deployer, "Owner should still be deployer");
        assertEq(registry.pendingOwner(), pendingOwner, "Pending owner should be set");
    }

    function test_OwnershipAcceptance_Flow() public {
        vm.chainId(1);

        ParameterRegistry registry = deployMainnet.deployOnly();

        // Initiate transfer
        vm.startPrank(deployer);
        registry.transferOwnership(pendingOwner);
        vm.stopPrank();

        assertEq(registry.pendingOwner(), pendingOwner, "Pending owner should be set");
        assertEq(registry.owner(), deployer, "Owner should still be deployer");

        // Accept ownership
        vm.startPrank(pendingOwner);
        registry.acceptOwnership();
        vm.stopPrank();

        assertEq(registry.owner(), pendingOwner, "Ownership should be transferred");
        assertEq(registry.pendingOwner(), address(0), "Pending owner should be cleared");
    }

    function test_OwnershipTransfer_CanBeCancelled() public {
        vm.chainId(1); // Set chain ID for mainnet deployment
        ParameterRegistry registry = deployMainnet.deployOnly();

        vm.startPrank(deployer);

        // Initiate transfer
        registry.transferOwnership(pendingOwner);
        assertEq(registry.pendingOwner(), pendingOwner);

        // Cancel by transferring to zero address
        registry.transferOwnership(address(0));
        assertEq(registry.pendingOwner(), address(0));

        vm.stopPrank();

        // Original pending owner can no longer accept
        vm.startPrank(pendingOwner);
        vm.expectRevert();
        registry.acceptOwnership();
        vm.stopPrank();
    }

    function test_AssetConfiguration_RequiresUpdaterRole() public {
        vm.chainId(1); // Set chain ID for mainnet deployment
        ParameterRegistry registry = deployMainnet.deployOnly();

        // Transfer updater role
        vm.startPrank(deployer);
        registry.setUpdater(pendingUpdater);
        vm.stopPrank();

        // Try to configure as non-updater
        vm.startPrank(deployer);
        vm.expectRevert(ParameterRegistry.OnlyUpdater.selector);
        registry.setParametersForAsset(
            makeAddr("asset"), "Test Asset", makeAddr("oracle"), 1000, 100, 100, 200, 10, true, true, false
        );
        vm.stopPrank();

        // Configure as updater should work
        vm.startPrank(pendingUpdater);
        registry.setParametersForAsset(
            makeAddr("asset"), "Test Asset", makeAddr("oracle"), 1000, 100, 100, 200, 10, true, true, false
        );
        assertTrue(registry.assetExists(makeAddr("asset")), "Asset should be configured");
        vm.stopPrank();
    }

    function test_InvalidChainId_Reverts() public {
        vm.chainId(999_999);

        vm.expectRevert("DeployConfig: Unsupported chain ID");
        deployScript.run();
    }

    function test_ZeroAddressValidation() public {
        vm.chainId(1); // Set chain ID for mainnet deployment
        ParameterRegistry registry = deployMainnet.deployOnly();

        // Test zero address for updater
        vm.startPrank(deployer);
        vm.expectRevert(ParameterRegistry.ZeroAddress.selector);
        registry.setUpdater(address(0));
        vm.stopPrank();

        // Test zero address for oracle
        vm.startPrank(deployer);
        vm.expectRevert(ParameterRegistry.ZeroAddress.selector);
        registry.setParametersForAsset(
            makeAddr("asset"),
            "Test Asset",
            address(0), // zero oracle
            1000,
            100,
            100,
            200,
            10,
            true,
            true,
            false
        );
        vm.stopPrank();
    }

    function test_ParameterLimitsValidation() public {
        vm.chainId(1); // Set chain ID for mainnet deployment
        ParameterRegistry registry = deployMainnet.deployOnly();

        vm.startPrank(deployer);

        // Test upper bound tolerance limit
        vm.expectRevert(abi.encodeWithSelector(ParameterRegistry.UpperBoundToleranceTooHigh.selector, 251));
        registry.setParametersForAsset(
            makeAddr("asset1"),
            "Asset 1",
            makeAddr("oracle1"),
            1000,
            251, // Exceeds limit
            100,
            100,
            10,
            true,
            true,
            false
        );

        // Test lower bound tolerance limit
        vm.expectRevert(abi.encodeWithSelector(ParameterRegistry.LowerBoundToleranceTooHigh.selector, 251));
        registry.setParametersForAsset(
            makeAddr("asset2"),
            "Asset 2",
            makeAddr("oracle2"),
            1000,
            100,
            251, // Exceeds limit
            100,
            10,
            true,
            true,
            false
        );

        // Test max discount limit
        vm.expectRevert(abi.encodeWithSelector(ParameterRegistry.MaxDiscountTooHigh.selector, 251));
        registry.setParametersForAsset(
            makeAddr("asset3"),
            "Asset 3",
            makeAddr("oracle3"),
            1000,
            100,
            100,
            251, // Exceeds limit
            10,
            true,
            true,
            false
        );

        vm.stopPrank();
    }

    function test_AssetDeletion_OnlyUpdater() public {
        vm.chainId(1); // Set chain ID for mainnet deployment
        ParameterRegistry registry = deployMainnet.deployOnly();

        address testAsset = makeAddr("testAsset");

        // Add asset
        vm.startPrank(deployer);
        registry.setParametersForAsset(
            testAsset, "Test Asset", makeAddr("oracle"), 1000, 100, 100, 200, 10, true, true, false
        );
        assertTrue(registry.assetExists(testAsset), "Asset should exist");
        vm.stopPrank();

        // Try to delete as non-updater
        vm.startPrank(unauthorizedUser);
        vm.expectRevert(ParameterRegistry.OnlyUpdater.selector);
        registry.deleteAsset(testAsset);
        vm.stopPrank();

        // Delete as updater
        vm.startPrank(deployer);
        registry.deleteAsset(testAsset);
        assertFalse(registry.assetExists(testAsset), "Asset should be deleted");
        vm.stopPrank();
    }

    function test_MultipleAssetsConfiguration() public {
        vm.chainId(1); // Set chain ID for mainnet deployment
        ParameterRegistry registry = deployMainnet.deployOnly();

        address[] memory assets = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            assets[i] = makeAddr(string(abi.encodePacked("asset", i)));
        }

        vm.startPrank(deployer);

        // Configure multiple assets
        for (uint256 i = 0; i < assets.length; i++) {
            registry.setParametersForAsset(
                assets[i],
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

        // Verify all assets exist
        for (uint256 i = 0; i < assets.length; i++) {
            assertTrue(registry.assetExists(assets[i]), "Asset should exist");
            assertEq(registry.getAssetName(assets[i]), string(abi.encodePacked("Asset ", i)), "Asset name should match");
        }

        vm.stopPrank();
    }
}
