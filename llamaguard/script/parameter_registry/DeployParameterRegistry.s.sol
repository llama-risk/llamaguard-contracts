// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { ParameterRegistry } from "../../src/ParameterRegistry.sol";
import { BaseScript } from "../Base.s.sol";
import { DeployConfig } from "./DeployConfig.sol";
import { AssetConfigs } from "./AssetConfigs.sol";
import { console2 } from "forge-std/Test.sol";

/// @title DeployParameterRegistry
/// @notice Universal deployment script for ParameterRegistry contract with asset parameter configuration
/// @dev Supports deployment to Ethereum mainnet, Sepolia, and local Anvil networks with optional ownership transfer
contract DeployParameterRegistry is BaseScript {
    DeployConfig internal deployConfig;

    function setUp() public {
        deployConfig = new DeployConfig();
    }

    /// @notice Main deployment function with asset parameter configuration and optional ownership transfer
    /// @return parameterRegistry The deployed ParameterRegistry contract
    function run() public broadcast returns (ParameterRegistry parameterRegistry) {
        // Deploy the registry
        parameterRegistry = deployRegistry();

        // Configure asset parameters
        configureAssets(parameterRegistry);

        // Transfer roles if configured
        transferRolesIfNeeded(parameterRegistry);
    }

    /// @notice Deploy the ParameterRegistry contract
    /// @return parameterRegistry The deployed contract
    function deployRegistry() internal returns (ParameterRegistry parameterRegistry) {
        // Get the current chain ID
        uint256 chainId = block.chainid;
        console2.log("Deploying to chain ID:", chainId);

        // Get configuration based on deployment method
        DeployConfig.Config memory config = getConfig(chainId);

        // For initial deployment, use deployer as both owner and updater
        address initialOwner = broadcaster;
        address initialUpdater = broadcaster;

        // Log deployment parameters
        console2.log("Network:", config.networkName);
        console2.log("Deployer (initial owner/updater):", broadcaster);

        // Deploy the contract
        parameterRegistry = new ParameterRegistry(initialOwner, initialUpdater);

        // Log deployment result
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
        uint256 chainId = block.chainid;

        // Get asset configurations for the current chain
        AssetConfigs.AssetConfig[] memory assets = deployConfig.getAssetsByChainId(chainId);

        if (assets.length == 0) {
            console2.log("No assets to configure");
            return;
        }

        console2.log("Configuring", assets.length, "assets...");

        for (uint256 i = 0; i < assets.length; i++) {
            AssetConfigs.AssetConfig memory asset = assets[i];

            console2.log("Setting parameters for asset:", asset.assetName);
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
            console2.log("  Asset configured successfully");
        }

        console2.log("All assets configured successfully!");
    }

    /// @notice Transfer updater role and initiate ownership transfer if configured
    /// @param parameterRegistry The deployed registry contract
    function transferRolesIfNeeded(ParameterRegistry parameterRegistry) internal {
        uint256 chainId = block.chainid;
        DeployConfig.Config memory config = getConfig(chainId);

        bool rolesTransferred = false;

        // Transfer updater role (immediate) if configured
        if (config.pendingUpdater != address(0) && config.pendingUpdater != broadcaster) {
            console2.log("");
            console2.log("Transferring updater role...");
            console2.log("  From:", broadcaster);
            console2.log("  To:", config.pendingUpdater);

            parameterRegistry.setUpdater(config.pendingUpdater);

            console2.log("  [OK] Updater role transferred");
            require(parameterRegistry.updater() == config.pendingUpdater, "Updater not transferred correctly");
            rolesTransferred = true;
        }

        // Initiate ownership transfer (two-step process) if configured
        if (config.pendingOwner != address(0) && config.pendingOwner != broadcaster) {
            console2.log("");
            console2.log("Initiating ownership transfer (two-step process)...");
            console2.log("  Current owner:", broadcaster);
            console2.log("  Pending owner:", config.pendingOwner);

            parameterRegistry.transferOwnership(config.pendingOwner);

            console2.log("  [OK] Ownership transfer initiated");
            console2.log("  [PENDING] New owner must call acceptOwnership() to complete transfer");

            require(parameterRegistry.pendingOwner() == config.pendingOwner, "Pending owner not set correctly");
            rolesTransferred = true;
        }

        if (rolesTransferred) {
            console2.log("");
            console2.log("===========================================");
            console2.log("Deployment completed with role transfers!");
            console2.log("===========================================");
            console2.log("ParameterRegistry:", address(parameterRegistry));
            console2.log("Current owner:", parameterRegistry.owner());
            if (parameterRegistry.pendingOwner() != address(0)) {
                console2.log("Pending owner:", parameterRegistry.pendingOwner());
                console2.log("IMPORTANT: Pending owner must call acceptOwnership()");
            }
            console2.log("Current updater:", parameterRegistry.updater());
            console2.log("===========================================");
        }
    }

    /// @notice Get configuration based on priority: env vars > chain-specific config
    /// @param chainId The chain ID of the target network
    /// @return config The deployment configuration
    function getConfig(uint256 chainId) internal view returns (DeployConfig.Config memory config) {
        // First, try to get configuration from environment variables
        bool useEnvConfig = vm.envOr({ name: "USE_ENV_CONFIG", defaultValue: false });

        if (useEnvConfig) {
            console2.log("Using environment variable configuration");

            address owner = vm.envOr({ name: "OWNER_ADDRESS", defaultValue: address(0) });
            address updater = vm.envOr({ name: "UPDATER_ADDRESS", defaultValue: address(0) });
            address pendingOwner = vm.envOr({ name: "PENDING_OWNER_ADDRESS", defaultValue: address(0) });
            address pendingUpdater = vm.envOr({ name: "PENDING_UPDATER_ADDRESS", defaultValue: address(0) });

            // If env vars are set, use them
            if (owner != address(0) && updater != address(0)) {
                // Try to get network name, default to chain ID string if not set
                string memory networkName;
                try vm.envString("NETWORK_NAME") returns (string memory name) {
                    networkName = name;
                } catch {
                    networkName = string(abi.encodePacked("chain-", vm.toString(chainId)));
                }

                config = DeployConfig.Config({
                    owner: owner,
                    updater: updater,
                    pendingOwner: pendingOwner,
                    pendingUpdater: pendingUpdater,
                    networkName: networkName
                });
                return config;
            }
        }

        // Otherwise, use chain-specific configuration
        console2.log("Using chain-specific configuration");
        config = deployConfig.getConfigByChainId(chainId);
    }

    /// @notice Deploy only the registry without configuration
    /// @dev Useful when you want to deploy the registry but configure assets separately
    function deployOnly() public broadcast returns (ParameterRegistry parameterRegistry) {
        parameterRegistry = deployRegistry();
        console2.log("Registry deployed without asset configuration");
        console2.log("To configure assets, call configureAssetsManually() separately");
    }

    /// @notice Configure assets on an already deployed registry
    /// @dev Can be called separately after deployment if needed
    /// @param registryAddress The address of the deployed ParameterRegistry
    function configureAssetsManually(address registryAddress) public broadcast {
        require(registryAddress != address(0), "Registry address cannot be zero");
        ParameterRegistry parameterRegistry = ParameterRegistry(registryAddress);

        // Verify the registry is valid
        require(parameterRegistry.owner() != address(0), "Invalid registry contract");

        console2.log("Configuring assets on registry at:", registryAddress);
        configureAssets(parameterRegistry);
    }

    /// @notice Transfer roles on an already deployed and configured registry
    /// @dev Can be called separately after deployment and configuration
    /// @param registryAddress The address of the deployed ParameterRegistry
    function transferRolesManually(address registryAddress) public broadcast {
        require(registryAddress != address(0), "Registry address cannot be zero");
        ParameterRegistry parameterRegistry = ParameterRegistry(registryAddress);

        // Verify the registry is valid and we have owner permissions
        require(parameterRegistry.owner() == broadcaster, "Caller is not the owner");

        console2.log("Transferring roles on existing registry at:", registryAddress);
        transferRolesIfNeeded(parameterRegistry);
    }
}
