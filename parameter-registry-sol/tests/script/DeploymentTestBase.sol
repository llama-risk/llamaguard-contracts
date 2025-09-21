// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { Test } from "forge-std/src/Test.sol";
import { ParameterRegistry } from "../../src/ParameterRegistry.sol";
import { DeployConfig } from "../../script/DeployConfig.sol";
import { AssetConfigs } from "../../script/AssetConfigs.sol";

/// @title DeploymentTestBase
/// @notice Base contract for testing deployment scripts
/// @dev Provides common test utilities and setup
contract DeploymentTestBase is Test {
    DeployConfig internal deployConfig;
    address internal deployer;
    address internal pendingOwner;
    address internal pendingUpdater;

    function setUp() public virtual {
        // Setup test addresses
        deployer = makeAddr("deployer");
        pendingOwner = makeAddr("pendingOwner");
        pendingUpdater = makeAddr("pendingUpdater");

        // Deploy config
        deployConfig = new DeployConfig();

        // Fund deployer
        vm.deal(deployer, 10 ether);
    }

    /// @notice Helper to deploy registry directly without scripts
    function deployRegistry(address owner, address updater) internal returns (ParameterRegistry) {
        vm.prank(owner);
        return new ParameterRegistry(owner, updater);
    }

    /// @notice Helper to configure assets
    function configureAssets(ParameterRegistry registry, AssetConfigs.AssetConfig[] memory assets) internal {
        vm.startPrank(registry.updater());

        for (uint256 i = 0; i < assets.length; i++) {
            AssetConfigs.AssetConfig memory asset = assets[i];

            // Skip assets without oracle
            if (asset.oracle == address(0)) continue;

            registry.setParametersForAsset(
                asset.assetAddress,
                asset.assetName,
                asset.oracle,
                asset.maxExpectedApy,
                asset.upperBoundTolerance,
                asset.lowerBoundTolerance,
                asset.maxDiscount,
                asset.lookbackWindowSize,
                asset.isUpperBoundEnabled,
                asset.isLowerBoundEnabled,
                asset.isActionTakingEnabled
            );
        }

        vm.stopPrank();
    }

    /// @notice Helper to transfer roles
    function transferRoles(ParameterRegistry registry, address newUpdater, address newPendingOwner) internal {
        vm.startPrank(registry.owner());

        if (newUpdater != address(0) && newUpdater != registry.updater()) {
            registry.setUpdater(newUpdater);
        }

        if (newPendingOwner != address(0) && newPendingOwner != registry.owner()) {
            registry.transferOwnership(newPendingOwner);
        }

        vm.stopPrank();
    }
}
