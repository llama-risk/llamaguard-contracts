// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { Test } from "forge-std/Test.sol";
import { DeployMainnet } from "../../script/DeployMainnet.s.sol";
import { DeployConfig } from "../../script/DeployConfig.sol";
import { AssetConfigs } from "../../script/AssetConfigs.sol";
import { ParameterRegistry } from "../../src/ParameterRegistry.sol";
import { stdStorage, StdStorage } from "forge-std/StdStorage.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";

contract DeployMainnetTest is Test {
    DeployMainnet internal deployScript;
    DeployConfig internal deployConfig;

    address internal deployer;
    address internal pendingOwner;
    address internal pendingUpdater;

    using stdStorage for StdStorage;

    function setUp() public {
        // Set chain ID to mainnet for testing (without forking)
        vm.chainId(1);

        vm.setEnv("ETH_FROM", "0x0000000000000000000000000000000000000aBc");

        deployer = address(0x0000000000000000000000000000000000000aBc);
        pendingOwner = makeAddr("pendingOwner");
        pendingUpdater = makeAddr("pendingUpdater");

        // Deploy scripts
        deployScript = new DeployMainnet();
        deployConfig = new DeployConfig();

        deployScript.setUp();
        deployScript.setDeployConfig(deployConfig);

        // Fund deployer
        vm.deal(deployer, 10 ether);
    }

    function test_DeployMainnet_Success() public {
        // Mock the config to return proper addresses
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

        // Run full deployment
        ParameterRegistry registry = deployScript.run();

        // Verify deployment
        assertNotEq(address(registry), address(0), "Registry should be deployed");
        assertEq(registry.owner(), deployer, "Initial owner should be deployer");
        assertEq(registry.updater(), pendingUpdater, "Updater should be transferred");
        assertEq(registry.pendingOwner(), pendingOwner, "Pending owner should be set");
    }

    function test_DeployMainnet_RequiresMainnet() public {
        // Try to deploy on wrong chain (currently on forked mainnet, so this should pass)
        // To test failure, we'd need to switch to a different fork
        vm.chainId(11_155_111); // Sepolia

        vm.expectRevert("Not on Ethereum mainnet");
        deployScript.run();
    }

    function test_DeployOnly_Success() public {
        // Deploy only registry without configuration
        ParameterRegistry registry = deployScript.deployOnly();

        // Verify deployment
        assertNotEq(address(registry), address(0), "Registry should be deployed");
        assertEq(registry.owner(), deployer, "Owner should be deployer");
        assertEq(registry.updater(), deployer, "Updater should be deployer");
        assertEq(registry.pendingOwner(), address(0), "No pending owner should be set");
    }

    function test_ConfigureAssetsOnly_Success() public {
        // First deploy registry
        ParameterRegistry registry = deployScript.deployOnly();

        // Then configure assets
        deployScript.configureAssetsOnly(address(registry));

        // Verify assets are configured
        AssetConfigs.AssetConfig[] memory assets = deployConfig.getMainnetAssets();

        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i].oracle == address(0)) continue; // Skip assets without oracle

            (
                uint64 maxExpectedApy,
                uint32 upperBoundTolerance,
                uint32 lowerBoundTolerance,
                uint32 maxDiscount,
                uint80 lookbackWindowSize,
                bool isUpperBoundEnabled,
                bool isLowerBoundEnabled,
                bool isActionTakingEnabled
            ) = registry.getParametersForAsset(assets[i].assetAddress);

            assertEq(registry.getAssetName(assets[i].assetAddress), assets[i].assetName, "Asset name mismatch");
            assertEq(registry.getOracle(assets[i].assetAddress), assets[i].oracle, "Oracle mismatch");
            assertEq(maxExpectedApy, assets[i].maxExpectedApy, "Max APY mismatch");
        }
    }

    function test_ConfigureAssetsOnly_RequiresUpdater() public {
        // Deploy registry
        ParameterRegistry registry = deployScript.deployOnly();

        // Transfer updater role to someone else
        vm.startPrank(deployer);
        registry.setUpdater(pendingUpdater);
        vm.stopPrank();

        // Try to configure assets without updater role
        vm.expectRevert("Caller is not the updater");
        deployScript.configureAssetsOnly(address(registry));
    }

    function test_TransferRolesOnly_Success() public {
        // Mock the config to return proper addresses
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

        // Deploy registry first
        ParameterRegistry registry = deployScript.deployOnly();

        // Transfer roles
        deployScript.transferRolesOnly(address(registry));

        // Verify role transfers
        assertEq(registry.updater(), pendingUpdater, "Updater should be transferred");
        assertEq(registry.pendingOwner(), pendingOwner, "Pending owner should be set");
        assertEq(registry.owner(), deployer, "Owner should still be deployer until accepted");
    }

    function test_TransferRolesOnly_RequiresOwner() public {
        vm.mockCall(
            address(deployConfig),
            abi.encodeWithSelector(DeployConfig.getMainnetConfig.selector),
            abi.encode(
                DeployConfig.Config({
                    owner: address(10),
                    updater: address(10),
                    pendingOwner: pendingOwner,
                    pendingUpdater: pendingUpdater,
                    networkName: "mainnet"
                })
            )
        );
        // Deploy registry
        ParameterRegistry registry = deployScript.deployOnly();

        // Try to transfer roles as non-owner
        vm.startPrank(pendingOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, pendingOwner));
        registry.transferOwnership(pendingOwner);
        vm.stopPrank();
    }

    function test_AcceptOwnership_ManualTransfer() public {
        // Deploy registry
        ParameterRegistry registry = deployScript.deployOnly();

        // Manually initiate ownership transfer (bypassing the buggy transferRoles)
        vm.startPrank(deployer);
        registry.transferOwnership(pendingOwner);

        vm.stopPrank();

        // Accept ownership as pending owner
        vm.startPrank(pendingOwner);
        registry.acceptOwnership();
        vm.stopPrank();

        // Verify ownership transfer completed
        assertEq(registry.owner(), pendingOwner, "Ownership should be transferred");
        assertEq(registry.pendingOwner(), address(0), "Pending owner should be cleared");
    }

    function test_InvalidRegistryAddress_Reverts() public {
        // Test with zero address
        vm.expectRevert("Registry address cannot be zero");
        deployScript.configureAssetsOnly(address(0));
    }

    function test_AssetConfiguration_WithMissingOracle() public {
        // Deploy registry
        ParameterRegistry registry = deployScript.deployOnly();

        // Configure assets (some have oracle address 0)
        deployScript.configureAssetsOnly(address(registry));

        // Verify assets with oracle address 0 are still configured
        AssetConfigs.AssetConfig[] memory assets = deployConfig.getMainnetAssets();

        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i].oracle != address(0)) {
                // Asset with oracle should be fully configured
                assertEq(registry.getOracle(assets[i].assetAddress), assets[i].oracle, "Oracle should be set");
            }
            // All assets should have their parameters set regardless of oracle
            assertEq(registry.getAssetName(assets[i].assetAddress), assets[i].assetName, "Asset name should be set");
        }
    }

    function test_RequiredConfigValidation() public {
        // Test that deployment fails with invalid config
        vm.mockCall(
            address(deployConfig),
            abi.encodeWithSelector(DeployConfig.getMainnetConfig.selector),
            abi.encode(
                DeployConfig.Config({
                    owner: deployer,
                    updater: deployer,
                    pendingOwner: address(0), // Invalid - zero address
                    pendingUpdater: address(0), // Invalid - zero address
                    networkName: "mainnet"
                })
            )
        );

        // Deploy registry (should work)
        ParameterRegistry registry = deployScript.deployOnly();

        // Transfer roles should fail due to invalid config
        vm.expectRevert("Initial updater cannot be zero");
        deployScript.transferRolesOnly(address(registry));
    }

    function test_SameAddressValidation() public {
        // Test that deployment fails when pending addresses are same as deployer
        vm.mockCall(
            address(deployConfig),
            abi.encodeWithSelector(DeployConfig.getMainnetConfig.selector),
            abi.encode(
                DeployConfig.Config({
                    owner: deployer,
                    updater: deployer,
                    pendingOwner: deployer, // Same as deployer - should fail
                    pendingUpdater: deployer, // Same as deployer - should fail
                    networkName: "mainnet"
                })
            )
        );

        // Deploy registry (should work)
        ParameterRegistry registry = deployScript.deployOnly();

        // Transfer roles should fail
        vm.expectRevert("Initial updater cannot be the same as the deployer");
        deployScript.transferRolesOnly(address(registry));
    }
}
