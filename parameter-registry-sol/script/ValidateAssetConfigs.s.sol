// SPDX-License-Identifier: MIT
// NOTE: You need to deactivate the evm version in the foundry.toml for this script to work.
pragma solidity >=0.8.26 <0.9.0;

import { AssetConfigs } from "./AssetConfigs.sol";
import { console2 } from "forge-std/src/console2.sol";

// Interface for ERC20 token symbol() function
interface IERC20Symbol {
    function symbol() external view returns (string memory);
    function implementation() external view returns (address);
}

// Interface for ERC20 token name() function
interface IERC20Name {
    function name() external view returns (string memory);
}

// Interface for ERC20 token decimals() function
interface IERC20Decimals {
    function decimals() external view returns (uint8);
}

// Interface for oracle description() function
interface IOracleDescription {
    function description() external view returns (string memory);
}

/// @title ValidateAssetConfigs
/// @notice Script to validate asset configurations by making on-chain calls
/// @dev This script reads asset configs and calls symbol() on assets and description() on oracles
contract ValidateAssetConfigs {
    function run() public {
        console2.log("=== Asset Configuration Validation Script ===");
        console2.log("");

        // Get current chain ID
        uint256 chainId = block.chainid;
        console2.log("Current Chain ID:", chainId);
        console2.log("");

        // Create AssetConfigs instance
        AssetConfigs assetConfigs = new AssetConfigs();

        // Get assets for current chain
        AssetConfigs.AssetConfig[] memory assets = assetConfigs.getAssetsByChainId(chainId);

        console2.log("Found", assets.length, "assets configured for this chain");
        console2.log("");

        // Validate each asset
        for (uint256 i = 0; i < assets.length; i++) {
            console2.log("--- Asset", i + 1, "---");
            console2.log("Asset Name (from config):", assets[i].assetName);
            console2.log("Asset Address:", assets[i].assetAddress);
            console2.log("Oracle Address:", assets[i].oracle);
            // console2.log("Max Expected APY:", assets[i].maxExpectedApy, "BPS");
            // console2.log("Upper Bound Tolerance:", assets[i].upperBoundTolerance, "BPS");
            // console2.log("Lower Bound Tolerance:", assets[i].lowerBoundTolerance, "BPS");
            // console2.log("Max Discount:", assets[i].maxDiscount, "BPS");
            // console2.log("Lookback Window Size:", assets[i].lookbackWindowSize);
            // console2.log("Upper Bound Enabled:", assets[i].isUpperBoundEnabled);
            // console2.log("Lower Bound Enabled:", assets[i].isLowerBoundEnabled);
            // console2.log("Action Taking Enabled:", assets[i].isActionTakingEnabled);
            console2.log("");

            // Try to get asset information
            console2.log("On-chain Asset Information:");

            // Check if contract exists
            uint256 codeSize;
            address assetAddr = assets[i].assetAddress;
            assembly {
                codeSize := extcodesize(assetAddr)
            }

            if (codeSize == 0) {
                console2.log("  [ERROR] No contract deployed at this address");
            } else {
                console2.log("  [INFO] Contract exists (", codeSize, "bytes)");

                // Try symbol() first with gas limit
                try IERC20Symbol(assets[i].assetAddress).symbol{ gas: 100_000 }() returns (string memory symbol) {
                    console2.log("  [OK] Symbol:", symbol);
                } catch Error(string memory reason) {
                    console2.log("  [ERROR] Error calling symbol():", reason);
                } catch (bytes memory) {
                    console2.log("  [INFO] Implementation:", IERC20Symbol(assets[i].assetAddress).implementation());
                    console2.log("  [WARNING] symbol() not available - trying name()");

                    // Try name() as fallback with gas limit
                    try IERC20Name(assets[i].assetAddress).name{ gas: 100_000 }() returns (string memory name) {
                        console2.log("  [OK] Name:", name);
                    } catch Error(string memory reason) {
                        console2.log("  [ERROR] Error calling name():", reason);
                    } catch (bytes memory) {
                        console2.log("  [WARNING] name() not available - trying decimals()");

                        // Try decimals() as last resort with gas limit
                        try IERC20Decimals(assets[i].assetAddress).decimals{ gas: 50_000 }() returns (uint8 decimals) {
                            console2.log("  [OK] Decimals:", decimals);
                            console2.log("  [INFO] Contract exists but no standard ERC20 interface");
                        } catch Error(string memory reason) {
                            console2.log("  [ERROR] Error calling decimals():", reason);
                        } catch (bytes memory) {
                            console2.log("  [ERROR] Contract does not implement standard ERC20 interface");
                        }
                    }
                }
            }

            // Try to get oracle description
            console2.log("On-chain Oracle Description:");
            if (assets[i].oracle != address(0)) {
                try IOracleDescription(assets[i].oracle).description() returns (string memory description) {
                    console2.log("  [OK] Description:", description);
                } catch Error(string memory reason) {
                    console2.log("  [ERROR] Error calling description():", reason);
                } catch (bytes memory) {
                    console2.log("  [ERROR] Unknown error calling description()");
                }
            } else {
                console2.log("  [WARNING] No oracle address configured (address(0))");
            }

            console2.log("");
            console2.log("==========================================");
            console2.log("");
        }

        console2.log("=== Validation Complete ===");
        console2.log("Total assets processed:", assets.length);
    }

    /// @notice Validate assets for a specific chain ID
    /// @param targetChainId The chain ID to validate assets for
    function validateForChain(uint256 targetChainId) public {
        console2.log("=== Asset Configuration Validation for Chain ID:", targetChainId, "===");
        console2.log("");

        // Create AssetConfigs instance
        AssetConfigs assetConfigs = new AssetConfigs();

        // Check if chain is supported
        if (!assetConfigs.hasAssetsForChain(targetChainId)) {
            console2.log("[ERROR] Chain ID", targetChainId, "is not supported");
            return;
        }

        // Get assets for target chain
        AssetConfigs.AssetConfig[] memory assets = assetConfigs.getAssetsByChainId(targetChainId);

        console2.log("Found", assets.length, "assets configured for chain", targetChainId);
        console2.log("");

        // Validate each asset
        for (uint256 i = 0; i < assets.length; i++) {
            console2.log("--- Asset", i + 1, "---");
            console2.log("Asset Name (from config):", assets[i].assetName);
            console2.log("Asset Address:", assets[i].assetAddress);
            console2.log("Oracle Address:", assets[i].oracle);
            // console2.log("Max Expected APY:", assets[i].maxExpectedApy, "BPS");
            // console2.log("Upper Bound Tolerance:", assets[i].upperBoundTolerance, "BPS");
            // console2.log("Lower Bound Tolerance:", assets[i].lowerBoundTolerance, "BPS");
            // console2.log("Max Discount:", assets[i].maxDiscount, "BPS");
            // console2.log("Lookback Window Size:", assets[i].lookbackWindowSize);
            // console2.log("Upper Bound Enabled:", assets[i].isUpperBoundEnabled);
            // console2.log("Lower Bound Enabled:", assets[i].isLowerBoundEnabled);
            // console2.log("Action Taking Enabled:", assets[i].isActionTakingEnabled);
            console2.log("");

            // Note: We can't make actual on-chain calls for different chains from this script
            // This is just for configuration validation
            console2.log("Note: On-chain validation requires running on the target network");
            console2.log("");

            console2.log("==========================================");
            console2.log("");
        }

        console2.log("=== Configuration Validation Complete ===");
        console2.log("Total assets processed:", assets.length);
    }
}
