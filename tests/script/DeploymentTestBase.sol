// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { Test } from "forge-std/Test.sol";
import { ParameterRegistry } from "../../src/ParameterRegistry.sol";
import { DeployStructs } from "../../script/config/DeployStructs.sol";
import { MainnetConfig } from "../../script/config/MainnetConfig.sol";
import { SepoliaConfig } from "../../script/config/SepoliaConfig.sol";
import { AnvilConfig } from "../../script/config/AnvilConfig.sol";

/// @title DeploymentTestBase
/// @notice Base contract for testing deployment scripts
/// @dev Provides common test utilities and setup
contract DeploymentTestBase is Test {
    MainnetConfig internal mainnetConfig;
    SepoliaConfig internal sepoliaConfig;
    AnvilConfig internal anvilConfig;
    address internal deployer;
    address internal pendingOwner;
    address internal pendingUpdater;

    function setUp() public virtual {
        deployer = makeAddr("deployer");
        pendingOwner = makeAddr("pendingOwner");
        pendingUpdater = makeAddr("pendingUpdater");

        mainnetConfig = new MainnetConfig();
        sepoliaConfig = new SepoliaConfig();
        anvilConfig = new AnvilConfig();

        vm.deal(deployer, 10 ether);
    }

    /// @notice Helper to deploy registry directly without scripts
    function deployRegistry(address owner, address updater) internal returns (ParameterRegistry) {
        vm.prank(owner);
        return new ParameterRegistry(owner, updater);
    }

    /// @notice Helper to configure assets
    function configureAssets(ParameterRegistry registry, DeployStructs.AssetConfig[] memory assets) internal {
        vm.startPrank(registry.updater());

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
