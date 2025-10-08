// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { ParameterRegistry } from "../src/ParameterRegistry.sol";
import { BaseScript } from "./Base.s.sol";
import { DeployConfig } from "./DeployConfig.sol";
import { AssetConfigs } from "./AssetConfigs.sol";
import { console2 } from "forge-std/Test.sol";

/// @title DeployMainnet
/// @notice Mainnet deployment script for ParameterRegistry with ownership transfer workflow
/// @dev Deploys with deployer as initial owner/updater, configures assets, then transfers roles
contract DeployMainnet is BaseScript {
    DeployConfig internal deployConfig;

    function setUp() public {
        deployConfig = new DeployConfig();
    }

    function setDeployConfig(DeployConfig _deployConfig) public {
        deployConfig = _deployConfig;
    }

    /// @notice Main deployment function with ownership transfer workflow
    /// @dev 1. Deploy with deployer as owner/updater
    ///      2. Configure assets
    ///      3. Transfer updater role
    ///      4. Transfer ownership (two-step process)
    /// @return parameterRegistry The deployed ParameterRegistry contract
    function run() public broadcast returns (ParameterRegistry parameterRegistry) {
        require(block.chainid == 1, "Not on Ethereum mainnet");

        // Step 1: Deploy the registry with deployer as initial owner and updater
        parameterRegistry = deployRegistry();

        // Step 2: Configure asset parameters
        configureAssets(parameterRegistry);

        // Step 3: Transfer updater role and initiate ownership transfer
        transferRoles(parameterRegistry);

        console2.log("===========================================");
        console2.log("Mainnet deployment completed successfully!");
        console2.log("===========================================");
        console2.log("ParameterRegistry:", address(parameterRegistry));
        console2.log("Current owner:", parameterRegistry.owner());
        console2.log("Pending owner:", parameterRegistry.pendingOwner());
        console2.log("Current updater:", parameterRegistry.updater());
        console2.log("");
        console2.log("IMPORTANT: The pending owner must call acceptOwnership() to complete the transfer");
        console2.log("===========================================");
    }

    /// @notice Deploy the ParameterRegistry contract
    /// @return parameterRegistry The deployed contract
    function deployRegistry() internal returns (ParameterRegistry parameterRegistry) {
        console2.log("===========================================");
        console2.log("Deploying ParameterRegistry to Mainnet");
        console2.log("===========================================");

        // For mainnet, deployer starts as both owner and updater
        address initialOwner = broadcaster;
        address initialUpdater = broadcaster;

        console2.log("Deployer (initial owner/updater):", broadcaster);

        // Deploy the contract
        parameterRegistry = new ParameterRegistry(initialOwner, initialUpdater);

        console2.log("ParameterRegistry deployed at:", address(parameterRegistry));
        console2.log("Initial owner:", parameterRegistry.owner());
        console2.log("Initial updater:", parameterRegistry.updater());

        // Verify deployment
        require(parameterRegistry.owner() == initialOwner, "Owner not set correctly");
        require(parameterRegistry.updater() == initialUpdater, "Updater not set correctly");
    }

    /// @notice Configure asset parameters in the registry
    /// @param parameterRegistry The deployed registry contract
    function configureAssets(ParameterRegistry parameterRegistry) internal {
        console2.log("");
        console2.log("===========================================");
        console2.log("Configuring Assets");
        console2.log("===========================================");

        // Get asset configurations for mainnet
        AssetConfigs.AssetConfig[] memory assets = deployConfig.getMainnetAssets();

        if (assets.length == 0) {
            console2.log("No assets to configure (add them to DeployConfig.getMainnetAssets())");
            return;
        }

        console2.log("Configuring", assets.length, "assets...");

        for (uint256 i = 0; i < assets.length; i++) {
            AssetConfigs.AssetConfig memory asset = assets[i];

            console2.log("");
            console2.log("Setting parameters for asset", i + 1, ":", asset.assetName);
            console2.log("  Asset address:", asset.assetAddress);
            console2.log("  Oracle address:", asset.oracle);

            // Set parameters for the asset
            parameterRegistry.setParametersForAsset(
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

            console2.log("  Max Expected APY:", asset.maxExpectedApy, "BPS");
            console2.log("  Upper Bound Tolerance:", asset.upperBoundTolerance, "BPS");
            console2.log("  Lower Bound Tolerance:", asset.lowerBoundTolerance, "BPS");
            console2.log("  Max Discount:", asset.maxDiscount, "BPS");
            console2.log("  Lookback Window:", asset.lookbackWindowSize, "blocks");
            console2.log("  Upper Bound Enabled:", asset.isUpperBoundEnabled);
            console2.log("  Lower Bound Enabled:", asset.isLowerBoundEnabled);
            console2.log("  Action Taking Enabled:", asset.isActionTakingEnabled);
            console2.log("  [OK] Asset configured successfully");
        }

        console2.log("");
        console2.log("All assets configured successfully!");
    }

    /// @notice Transfer updater role and initiate ownership transfer
    /// @param parameterRegistry The deployed registry contract
    function transferRoles(ParameterRegistry parameterRegistry) internal {
        // Get the configuration
        DeployConfig.Config memory config = deployConfig.getMainnetConfig();

        require(config.pendingUpdater != address(0), "Initial updater cannot be zero");
        require(config.pendingUpdater != broadcaster, "Initial updater cannot be the same as the deployer");

        require(config.pendingOwner != address(0), "Initial owner cannot be zero");
        require(config.pendingOwner != broadcaster, "Initial owner cannot be the same as the deployer");

        console2.log("");
        console2.log("===========================================");
        console2.log("Transferring Roles");
        console2.log("===========================================");

        // Transfer updater role (immediate)
        console2.log("Transferring updater role...");
        console2.log("  From:", broadcaster);
        console2.log("  To:", config.pendingUpdater);

        parameterRegistry.setUpdater(config.pendingUpdater);

        console2.log("  [OK] Updater role transferred");
        require(parameterRegistry.updater() == config.pendingUpdater, "Updater not transferred correctly");

        // Initiate ownership transfer (two-step process)
        console2.log("");
        console2.log("Initiating ownership transfer (two-step process)...");
        console2.log("  Current owner:", broadcaster);
        console2.log("  Pending owner:", config.pendingOwner);

        parameterRegistry.transferOwnership(config.pendingOwner);

        console2.log("  [OK] Ownership transfer initiated");
        console2.log("  [PENDING] New owner must call acceptOwnership() to complete transfer");

        require(parameterRegistry.pendingOwner() == config.pendingOwner, "Pending owner not set correctly");
    }

    /// @notice Deploy only the registry without configuration or role transfers
    /// @dev Useful for testing or when configuration will be done separately
    /// @return parameterRegistry The deployed contract
    function deployOnly() public broadcast returns (ParameterRegistry parameterRegistry) {
        require(block.chainid == 1, "Not on Ethereum mainnet");
        parameterRegistry = deployRegistry();
        console2.log("");
        console2.log("Registry deployed without configuration or role transfers");
    }

    /// @notice Configure assets on an already deployed registry
    /// @dev Can be called separately after deployment if needed
    /// @param registryAddress The address of the deployed ParameterRegistry
    function configureAssetsOnly(address registryAddress) public broadcast {
        require(registryAddress != address(0), "Registry address cannot be zero");
        require(block.chainid == 1, "Not on Ethereum mainnet");

        ParameterRegistry parameterRegistry = ParameterRegistry(registryAddress);

        // Verify the registry is valid and we have updater permissions
        require(parameterRegistry.owner() != address(0), "Invalid registry contract");
        require(parameterRegistry.updater() == broadcaster, "Caller is not the updater");

        console2.log("Configuring assets on existing registry at:", registryAddress);
        configureAssets(parameterRegistry);
    }

    /// @notice Transfer roles on an already deployed and configured registry
    /// @dev Can be called separately after deployment and configuration
    /// @param registryAddress The address of the deployed ParameterRegistry
    function transferRolesOnly(address registryAddress) public broadcast {
        require(registryAddress != address(0), "Registry address cannot be zero");
        require(block.chainid == 1, "Not on Ethereum mainnet");

        ParameterRegistry parameterRegistry = ParameterRegistry(registryAddress);

        // Verify the registry is valid and we have owner permissions
        require(parameterRegistry.owner() == broadcaster, "Caller is not the owner");

        console2.log("Transferring roles on existing registry at:", registryAddress);
        transferRoles(parameterRegistry);
    }
}
