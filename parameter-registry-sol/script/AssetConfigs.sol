// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

/// @title AssetConfigs
/// @notice Centralized asset configuration for all networks
/// @dev This contract provides all asset configurations for different chains
contract AssetConfigs {
    /// @notice Error thrown when an unsupported chain ID is provided
    error UnsupportedChainId();
    /// @notice Asset parameter configuration structure

    struct AssetConfig {
        address assetAddress;
        string assetName;
        address oracle;
        uint64 maxExpectedApy; // BPS format (e.g., 500 = 5%)
        uint32 upperBoundTolerance; // BPS format (e.g., 100 = 1%)
        uint32 lowerBoundTolerance; // BPS format (e.g., 50 = 0.5%)
        uint32 maxDiscount; // BPS format (e.g., 200 = 2%)
        uint80 lookbackWindowSize;
        bool isUpperBoundEnabled;
        bool isLowerBoundEnabled;
        bool isActionTakingEnabled;
    }

    // ============================================
    // ETHEREUM MAINNET ASSETS (Chain ID: 1)
    // ============================================

    /// @notice Returns asset configurations for Ethereum mainnet
    /// @return assets Array of asset configurations
    function getMainnetAssets() public pure returns (AssetConfig[] memory) {
        AssetConfig[] memory assets = new AssetConfig[](5);

        assets[0] = AssetConfig({
            assetAddress: address(0x5a0F93D040De44e78F251b03c43be9CF317Dcf64),
            assetName: "JAAA",
            oracle: address(0x1E41Ef40AC148706c114534E8192Ca608f80fC48),
            maxExpectedApy: 520, // 5.2%
            upperBoundTolerance: 50, // 0.5%
            lowerBoundTolerance: 10, // 0.1%
            maxDiscount: 75, // 0.75%
            lookbackWindowSize: 4, // 1 update per day
            isUpperBoundEnabled: true,
            isLowerBoundEnabled: true,
            isActionTakingEnabled: false
        });

        assets[1] = AssetConfig({
            assetAddress: address(0x43415eB6ff9DB7E26A15b704e7A3eDCe97d31C4e),
            assetName: "USTB",
            oracle: address(0xde49c7B5C0E54b1624ED21C7D88bA6593d444Aa0),
            maxExpectedApy: 415, // 4.15%
            upperBoundTolerance: 15, // 0.15%
            lowerBoundTolerance: 5, // 0.05%
            maxDiscount: 10, // 0.1%
            lookbackWindowSize: 4, // 1 update per day
            isUpperBoundEnabled: true,
            isLowerBoundEnabled: true,
            isActionTakingEnabled: false
        });

        assets[2] = AssetConfig({
            assetAddress: address(0x8c213ee79581Ff4984583C6a801e5263418C4b86),
            assetName: "JTRSY",
            oracle: address(0x23adce82907D20c509101E2Af0723A9e16224EFb),
            maxExpectedApy: 390, // 3.9%
            upperBoundTolerance: 15, // 0.15%
            lowerBoundTolerance: 5, // 0.05%
            maxDiscount: 10, // 0.1%
            lookbackWindowSize: 4, // 1 update per day
            isUpperBoundEnabled: true,
            isLowerBoundEnabled: true,
            isActionTakingEnabled: false
        });

        assets[3] = AssetConfig({
            assetAddress: address(0x14d60E7FDC0D71d8611742720E4C50E7a974020c),
            assetName: "USCC",
            oracle: address(0x19e2d716288751c5A59deaB61af012D5DF895962),
            maxExpectedApy: 2500, // 25%
            upperBoundTolerance: 50, // 0.5%
            lowerBoundTolerance: 10, // 0.1%
            maxDiscount: 40, // 0.4%
            lookbackWindowSize: 4, // 1 update per day
            isUpperBoundEnabled: true,
            isLowerBoundEnabled: true,
            isActionTakingEnabled: false
        });

        assets[4] = AssetConfig({
            assetAddress: address(0x136471a34f6ef19fE571EFFC1CA711fdb8E49f2b),
            assetName: "USYC",
            oracle: address(0xE8E65Fb9116875012F5990Ecaab290B3531DbeB9),
            maxExpectedApy: 420, // 4.2%
            upperBoundTolerance: 15, // 0.15%
            lowerBoundTolerance: 5, // 0.05%
            maxDiscount: 10, // 0.1%
            lookbackWindowSize: 4, // 1 update per day
            isUpperBoundEnabled: true,
            isLowerBoundEnabled: true,
            isActionTakingEnabled: false
        });

        return assets;
    }

    // ============================================
    // SEPOLIA TESTNET ASSETS (Chain ID: 11155111)
    // ============================================

    /// @notice Returns asset configurations for Sepolia testnet
    /// @return assets Array of asset configurations
    function getSepoliaAssets() public pure returns (AssetConfig[] memory) {
        AssetConfig[] memory assets = new AssetConfig[](1);

        // Single test asset configuration for Sepolia
        assets[0] = AssetConfig({
            assetAddress: 0x14d60E7FDC0D71d8611742720E4C50E7a974020c,
            assetName: "USCC",
            oracle: 0xE38b0917888d0d5d8d03B7371d5214A1aF8e1892,
            maxExpectedApy: 2500, // 25% max APY
            upperBoundTolerance: 50, // 0.5% tolerance
            lowerBoundTolerance: 10, // 0.1% tolerance
            maxDiscount: 40, // 0.4% max discount
            lookbackWindowSize: 7,
            isUpperBoundEnabled: true,
            isLowerBoundEnabled: true,
            isActionTakingEnabled: false
        });

        return assets;
    }

    // ============================================
    // ANVIL LOCAL ASSETS (Chain ID: 31337)
    // ============================================

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

    // ============================================
    // HELPER FUNCTIONS
    // ============================================

    /// @notice Returns asset configurations based on chain ID
    /// @param chainId The chain ID of the target network
    /// @return assets Array of asset configurations
    function getAssetsByChainId(uint256 chainId) public pure returns (AssetConfig[] memory) {
        if (chainId == 1) {
            // Ethereum mainnet
            return getMainnetAssets();
        } else if (chainId == 11_155_111) {
            // Sepolia testnet
            return getSepoliaAssets();
        } else if (chainId == 31_337) {
            // Anvil local network
            return getAnvilAssets();
        } else {
            revert UnsupportedChainId();
        }
    }

    /// @notice Check if a chain has asset configurations
    /// @param chainId The chain ID to check
    /// @return True if the chain has configurations, false otherwise
    function hasAssetsForChain(uint256 chainId) public pure returns (bool) {
        return chainId == 1 || chainId == 11_155_111 || chainId == 31_337;
    }
}
