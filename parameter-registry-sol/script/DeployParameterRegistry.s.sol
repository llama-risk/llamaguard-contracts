// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29 <0.9.0;

import { ParameterRegistry } from "../src/ParameterRegistry.sol";
import { BaseScript } from "./Base.s.sol";
import { DeployConfig } from "./DeployConfig.sol";
import { console2 } from "forge-std/src/console2.sol";

/// @title DeployParameterRegistry
/// @notice Deployment script for ParameterRegistry contract with asset parameter configuration
/// @dev Supports deployment to Base mainnet, Base Sepolia, and local Anvil networks
contract DeployParameterRegistry is BaseScript {
    DeployConfig internal deployConfig;

    function setUp() public {
        deployConfig = new DeployConfig();
    }

    /// @notice Main deployment function with asset parameter configuration
    /// @return parameterRegistry The deployed ParameterRegistry contract
    function run() public broadcast returns (ParameterRegistry parameterRegistry) {
        // Deploy the registry
        parameterRegistry = deployRegistry();

        // Configure asset parameters
        configureAssets(parameterRegistry);
    }

    /// @notice Deploy the ParameterRegistry contract
    /// @return parameterRegistry The deployed contract
    function deployRegistry() internal returns (ParameterRegistry parameterRegistry) {
        // Get the current chain ID
        uint256 chainId = block.chainid;
        console2.log("Deploying to chain ID:", chainId);

        // Get configuration based on deployment method
        DeployConfig.Config memory config = getConfig(chainId);

        // Validate configuration
        require(config.owner != address(0), "Owner address cannot be zero");
        require(config.updater != address(0), "Updater address cannot be zero");

        // Log deployment parameters
        console2.log("Network:", config.networkName);
        console2.log("Owner:", config.owner);
        console2.log("Updater:", config.updater);
        console2.log("Deployer:", broadcaster);

        // Deploy the contract
        parameterRegistry = new ParameterRegistry(config.owner, config.updater);

        // Log deployment result
        console2.log("ParameterRegistry deployed at:", address(parameterRegistry));
        console2.log("Owner set to:", parameterRegistry.owner());
        console2.log("Updater set to:", parameterRegistry.updater());

        // Verify deployment
        require(parameterRegistry.owner() == config.owner, "Owner not set correctly");
        require(parameterRegistry.updater() == config.updater, "Updater not set correctly");
    }

    /// @notice Configure asset parameters in the registry
    /// @param parameterRegistry The deployed registry contract
    function configureAssets(ParameterRegistry parameterRegistry) internal {
        uint256 chainId = block.chainid;

        // Get asset configurations for the current chain
        DeployConfig.AssetConfig[] memory assets = deployConfig.getAssetsByChainId(chainId);

        console2.log("Configuring", assets.length, "assets...");

        // Get the updater address from config
        DeployConfig.Config memory config = getConfig(chainId);

        // Note: The updater needs to be the broadcaster for setting parameters
        // In production, ensure the deployer has updater permissions or deploy in two steps
        require(
            broadcaster == config.updater,
            "Deployer must be the updater to set parameters. Deploy registry first, then configure assets separately."
        );

        for (uint256 i = 0; i < assets.length; i++) {
            DeployConfig.AssetConfig memory asset = assets[i];

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
            console2.log("  Lookback Window:", asset.lookbackWindowSize, "hours");
            console2.log("  Upper Bound Enabled:", asset.isUpperBoundEnabled);
            console2.log("  Lower Bound Enabled:", asset.isLowerBoundEnabled);
            console2.log("  Action Taking Enabled:", asset.isActionTakingEnabled);
            console2.log("  Asset configured successfully");
        }

        console2.log("All assets configured successfully!");
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

            // If env vars are set, use them
            if (owner != address(0) && updater != address(0)) {
                // Try to get network name, default to chain ID string if not set
                string memory networkName;
                try vm.envString("NETWORK_NAME") returns (string memory name) {
                    networkName = name;
                } catch {
                    networkName = string(abi.encodePacked("chain-", vm.toString(chainId)));
                }

                config = DeployConfig.Config({ owner: owner, updater: updater, networkName: networkName });
                return config;
            }
        }

        // Otherwise, use chain-specific configuration
        console2.log("Using chain-specific configuration");
        config = deployConfig.getConfigByChainId(chainId);
    }

    /// @notice Deploy to Base mainnet specifically
    /// @dev Convenience function for Base mainnet deployment
    function deployToBaseMainnet() public broadcast returns (ParameterRegistry) {
        require(block.chainid == 8453, "Not on Base mainnet");
        return run();
    }

    /// @notice Deploy to Base Sepolia testnet specifically
    /// @dev Convenience function for Base Sepolia deployment
    function deployToBaseSepolia() public broadcast returns (ParameterRegistry) {
        require(block.chainid == 84_532, "Not on Base Sepolia");
        return run();
    }

    /// @notice Deploy without configuring assets
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
}
