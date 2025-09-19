// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29 <0.9.0;

import { ParameterRegistry } from "../src/ParameterRegistry.sol";
import { BaseScript } from "./Base.s.sol";
import { DeployConfig } from "./DeployConfig.sol";
import { console2 } from "forge-std/src/console2.sol";

/// @title DeployMainnetSepolia
/// @notice Deployment script specifically for Mainnet-Sepolia with single asset configuration
/// @dev Specialized deployment script for Ethereum Mainnet and Sepolia testnet
contract DeployMainnetSepolia is BaseScript {
    DeployConfig internal deployConfig;

    function setUp() public {
        deployConfig = new DeployConfig();
    }

    /// @notice Main deployment function for mainnet-sepolia with single asset
    /// @return parameterRegistry The deployed ParameterRegistry contract
    function run() public broadcast returns (ParameterRegistry parameterRegistry) {
        // Deploy the registry
        parameterRegistry = deployRegistry();

        // Configure single asset
        configureSingleAsset(parameterRegistry);
    }

    /// @notice Deploy the ParameterRegistry contract
    /// @return parameterRegistry The deployed contract
    function deployRegistry() internal returns (ParameterRegistry parameterRegistry) {
        uint256 chainId = block.chainid;
        console2.log("Deploying to chain ID:", chainId);

        // Validate we're on the correct network
        require(
            chainId == 1 || chainId == 11_155_111, "This script is only for Ethereum Mainnet (1) or Sepolia (11155111)"
        );

        // Get configuration
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

    /// @notice Configure single asset in the registry
    /// @param parameterRegistry The deployed registry contract
    function configureSingleAsset(ParameterRegistry parameterRegistry) internal {
        uint256 chainId = block.chainid;

        // Get single asset configuration for the current chain
        DeployConfig.AssetConfig[] memory assets = deployConfig.getAssetsByChainId(chainId);

        // Ensure we only have one asset
        require(assets.length == 1, "This deployment script expects exactly one asset");

        console2.log("Configuring single asset...");

        // Get the updater address from config
        DeployConfig.Config memory config = getConfig(chainId);

        // Note: The updater needs to be the broadcaster for setting parameters
        require(
            broadcaster == config.updater,
            "Deployer must be the updater to set parameters. Deploy registry first, then configure asset separately."
        );

        DeployConfig.AssetConfig memory asset = assets[0];

        console2.log("Setting parameters for asset:", asset.assetName);
        console2.log("  Asset address:", asset.assetAddress);
        console2.log("  Oracle address:", asset.oracle);

        // Set parameters for the single asset
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

        console2.log("Single asset configuration complete!");
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
                string memory networkName;
                try vm.envString("NETWORK_NAME") returns (string memory name) {
                    networkName = name;
                } catch {
                    if (chainId == 1) {
                        networkName = "ethereum-mainnet";
                    } else if (chainId == 11_155_111) {
                        networkName = "sepolia";
                    } else {
                        networkName = string(abi.encodePacked("chain-", vm.toString(chainId)));
                    }
                }

                config = DeployConfig.Config({ owner: owner, updater: updater, networkName: networkName });
                return config;
            }
        }

        // Otherwise, use chain-specific configuration
        console2.log("Using chain-specific configuration");
        config = deployConfig.getConfigByChainId(chainId);
    }

    /// @notice Deploy to Sepolia testnet specifically
    /// @dev Convenience function for Sepolia deployment
    function deployToSepolia() public broadcast returns (ParameterRegistry) {
        require(block.chainid == 11_155_111, "Not on Sepolia testnet");
        return run();
    }

    /// @notice Deploy without configuring the asset
    /// @dev Useful when you want to deploy the registry but configure the asset separately
    function deployOnly() public broadcast returns (ParameterRegistry parameterRegistry) {
        parameterRegistry = deployRegistry();
        console2.log("Registry deployed without asset configuration");
        console2.log("To configure the asset, call configureAssetManually() separately");
    }

    /// @notice Configure the single asset on an already deployed registry
    /// @dev Can be called separately after deployment if needed
    /// @param registryAddress The address of the deployed ParameterRegistry
    function configureAssetManually(address registryAddress) public broadcast {
        require(registryAddress != address(0), "Registry address cannot be zero");
        ParameterRegistry parameterRegistry = ParameterRegistry(registryAddress);

        // Verify the registry is valid
        require(parameterRegistry.owner() != address(0), "Invalid registry contract");

        console2.log("Configuring single asset on registry at:", registryAddress);
        configureSingleAsset(parameterRegistry);
    }
}
