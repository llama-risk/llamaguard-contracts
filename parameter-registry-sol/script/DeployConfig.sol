// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29 <0.9.0;

/// @title DeployConfig
/// @notice Configuration contract for deployment parameters across different networks
/// @dev This contract provides centralized configuration for deploying ParameterRegistry
contract DeployConfig {
    /// @notice Deployment configuration structure
    struct Config {
        address owner;
        address updater;
        string networkName;
    }

    /// @notice Asset parameter configuration structure
    struct AssetConfig {
        address assetAddress;
        string assetName;
        address oracle;
        uint256 maxExpectedApy; // BPS format (e.g., 500 = 5%)
        uint256 upperBoundTolerance; // BPS format (e.g., 100 = 1%)
        uint256 lowerBoundTolerance; // BPS format (e.g., 50 = 0.5%)
        uint256 maxDiscount; // BPS format (e.g., 200 = 2%)
        uint80 lookbackWindowSize;
        bool isUpperBoundEnabled;
        bool isLowerBoundEnabled;
        bool isActionTakingEnabled;
    }

    /// @notice Returns configuration for Base mainnet
    /// @return config The deployment configuration
    function getBaseMainnetConfig() public pure returns (Config memory) {
        return Config({
            owner: 0xb0AD0E3A19490E9145bE9Ad45F7B285eb71756F6, // TODO: Set actual owner address
            updater: 0xb0AD0E3A19490E9145bE9Ad45F7B285eb71756F6, // TODO: Set actual updater address
            networkName: "base-mainnet"
        });
    }

    /// @notice Returns asset configurations for Base mainnet
    /// @return assets Array of asset configurations
    function getBaseMainnetAssets() public pure returns (AssetConfig[] memory) {
        AssetConfig[] memory assets = new AssetConfig[](3);

        // Example: USDC configuration
        assets[0] = AssetConfig({
            assetAddress: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913, // USDC on Base
            assetName: "USD Coin",
            oracle: 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B, // USDC/USD price feed on Base
            maxExpectedApy: 1000, // 10% max APY
            upperBoundTolerance: 100, // 1% tolerance
            lowerBoundTolerance: 50, // 0.5% tolerance
            maxDiscount: 200, // 2% max discount
            lookbackWindowSize: 24, // 24 hours lookback
            isUpperBoundEnabled: true,
            isLowerBoundEnabled: true,
            isActionTakingEnabled: false
        });

        // Example: WETH configuration
        assets[1] = AssetConfig({
            assetAddress: 0x4200000000000000000000000000000000000006, // WETH on Base
            assetName: "Wrapped Ether",
            oracle: 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70, // ETH/USD price feed on Base
            maxExpectedApy: 2000, // 20% max APY
            upperBoundTolerance: 150, // 1.5% tolerance
            lowerBoundTolerance: 100, // 1% tolerance
            maxDiscount: 250, // 2.5% max discount
            lookbackWindowSize: 48, // 48 hours lookback
            isUpperBoundEnabled: true,
            isLowerBoundEnabled: true,
            isActionTakingEnabled: true
        });

        // Example: DAI configuration
        assets[2] = AssetConfig({
            assetAddress: 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb, // DAI on Base
            assetName: "Dai Stablecoin",
            oracle: 0x591e79239a7d679378eC8c847e5038150364C78F, // DAI/USD price feed on Base
            maxExpectedApy: 800, // 8% max APY
            upperBoundTolerance: 75, // 0.75% tolerance
            lowerBoundTolerance: 75, // 0.75% tolerance
            maxDiscount: 150, // 1.5% max discount
            lookbackWindowSize: 12, // 12 hours lookback
            isUpperBoundEnabled: true,
            isLowerBoundEnabled: false,
            isActionTakingEnabled: false
        });

        return assets;
    }

    /// @notice Returns configuration for Base Sepolia testnet
    /// @return config The deployment configuration
    function getBaseSepoliaConfig() public pure returns (Config memory) {
        return Config({
            owner: 0x0000000000000000000000000000000000000000, // TODO: Set actual owner address
            updater: 0x0000000000000000000000000000000000000000, // TODO: Set actual updater address
            networkName: "base-sepolia"
        });
    }

    /// @notice Returns asset configurations for Base Sepolia testnet
    /// @return assets Array of asset configurations
    function getBaseSepoliaAssets() public pure returns (AssetConfig[] memory) {
        AssetConfig[] memory assets = new AssetConfig[](2);

        // Test asset 1
        assets[0] = AssetConfig({
            assetAddress: 0x0000000000000000000000000000000000000001, // Dummy test asset
            assetName: "Test Token 1",
            oracle: 0x0000000000000000000000000000000000000002, // Dummy oracle
            maxExpectedApy: 500, // 5% max APY
            upperBoundTolerance: 50, // 0.5% tolerance
            lowerBoundTolerance: 50, // 0.5% tolerance
            maxDiscount: 100, // 1% max discount
            lookbackWindowSize: 6, // 6 hours lookback
            isUpperBoundEnabled: true,
            isLowerBoundEnabled: true,
            isActionTakingEnabled: false
        });

        // Test asset 2
        assets[1] = AssetConfig({
            assetAddress: 0x0000000000000000000000000000000000000003, // Dummy test asset
            assetName: "Test Token 2",
            oracle: 0x0000000000000000000000000000000000000004, // Dummy oracle
            maxExpectedApy: 1500, // 15% max APY
            upperBoundTolerance: 200, // 2% tolerance
            lowerBoundTolerance: 150, // 1.5% tolerance
            maxDiscount: 225, // 2.25% max discount
            lookbackWindowSize: 36, // 36 hours lookback
            isUpperBoundEnabled: false,
            isLowerBoundEnabled: true,
            isActionTakingEnabled: true
        });

        return assets;
    }

    /// @notice Returns configuration for local Anvil network
    /// @return config The deployment configuration
    function getAnvilConfig() public pure returns (Config memory) {
        // Default test addresses for local development
        // Using same account for both owner and updater for easier testing
        return Config({
            owner: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, // Anvil account 0
            updater: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, // Anvil account 0 (same as owner for testing)
            networkName: "anvil"
        });
    }

    /// @notice Returns asset configurations for Anvil local network
    /// @return assets Array of asset configurations
    function getAnvilAssets() public pure returns (AssetConfig[] memory) {
        AssetConfig[] memory assets = new AssetConfig[](3);

        // Mock USDC
        assets[0] = AssetConfig({
            assetAddress: 0x5FbDB2315678afecb367f032d93F642f64180aa3, // Mock address
            assetName: "Mock USDC",
            oracle: 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512, // Mock oracle
            maxExpectedApy: 1200, // 12% max APY
            upperBoundTolerance: 100, // 1% tolerance
            lowerBoundTolerance: 100, // 1% tolerance
            maxDiscount: 200, // 2% max discount
            lookbackWindowSize: 24,
            isUpperBoundEnabled: true,
            isLowerBoundEnabled: true,
            isActionTakingEnabled: true
        });

        // Mock WETH
        assets[1] = AssetConfig({
            assetAddress: 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0, // Mock address
            assetName: "Mock WETH",
            oracle: 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9, // Mock oracle
            maxExpectedApy: 5000, // 50% max APY (volatile asset)
            upperBoundTolerance: 250, // 2.5% tolerance (max allowed)
            lowerBoundTolerance: 200, // 2% tolerance
            maxDiscount: 250, // 2.5% max discount (max allowed)
            lookbackWindowSize: 72,
            isUpperBoundEnabled: true,
            isLowerBoundEnabled: false,
            isActionTakingEnabled: true
        });

        // Mock Stablecoin
        assets[2] = AssetConfig({
            assetAddress: 0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9, // Mock address
            assetName: "Mock Stable",
            oracle: 0x5FC8d32690cc91D4c39d9d3abcBD16989F875707, // Mock oracle
            maxExpectedApy: 300, // 3% max APY (conservative)
            upperBoundTolerance: 25, // 0.25% tolerance
            lowerBoundTolerance: 25, // 0.25% tolerance
            maxDiscount: 50, // 0.5% max discount
            lookbackWindowSize: 12,
            isUpperBoundEnabled: true,
            isLowerBoundEnabled: true,
            isActionTakingEnabled: false
        });

        return assets;
    }

    /// @notice Returns configuration based on chain ID
    /// @param chainId The chain ID of the target network
    /// @return config The deployment configuration
    function getConfigByChainId(uint256 chainId) public pure returns (Config memory) {
        if (chainId == 8453) {
            // Base mainnet
            return getBaseMainnetConfig();
        } else if (chainId == 84_532) {
            // Base Sepolia testnet
            return getBaseSepoliaConfig();
        } else if (chainId == 31_337) {
            // Anvil local network
            return getAnvilConfig();
        } else {
            revert("Unsupported chain ID");
        }
    }

    /// @notice Returns asset configurations based on chain ID
    /// @param chainId The chain ID of the target network
    /// @return assets Array of asset configurations
    function getAssetsByChainId(uint256 chainId) public pure returns (AssetConfig[] memory) {
        if (chainId == 8453) {
            // Base mainnet
            return getBaseMainnetAssets();
        } else if (chainId == 84_532) {
            // Base Sepolia testnet
            return getBaseSepoliaAssets();
        } else if (chainId == 31_337) {
            // Anvil local network
            return getAnvilAssets();
        } else {
            revert("Unsupported chain ID for assets");
        }
    }
}
