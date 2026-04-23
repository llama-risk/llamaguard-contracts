// SPDX-License-Identifier: MIT
// NOTE: You need to deactivate the evm version in the foundry.toml for this script to work.
pragma solidity >=0.8.26 <0.9.0;

import { DeployStructs } from "../config/DeployStructs.sol";
import { MainnetConfig } from "../config/MainnetConfig.sol";
import { SepoliaConfig } from "../config/SepoliaConfig.sol";
import { AnvilConfig } from "../config/AnvilConfig.sol";
import { console2 } from "forge-std/Test.sol";

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
/// @dev Uses consolidated config files for asset parameters
contract ValidateAssetConfigs {
    function run() public {
        console2.log("=== Asset Configuration Validation Script ===");
        console2.log("");

        uint256 chainId = block.chainid;
        console2.log("Current Chain ID:", chainId);
        console2.log("");

        DeployStructs.AssetConfig[] memory assets = _getAssets(chainId);

        console2.log("Found", assets.length, "assets configured for this chain");
        console2.log("");

        for (uint256 i = 0; i < assets.length; i++) {
            _validateAsset(assets[i], i);
        }

        console2.log("=== Validation Complete ===");
        console2.log("Total assets processed:", assets.length);
    }

    function _validateAsset(DeployStructs.AssetConfig memory asset, uint256 index) internal view {
        console2.log("--- Asset", index + 1, "---");
        console2.log("Asset Name (from config):", asset.assetName);
        console2.log("Asset Address:", asset.assetAddress);
        console2.log("Oracle Address:", asset.oracle);
        console2.log("");

        // Check if contract exists
        uint256 codeSize;
        address assetAddr = asset.assetAddress;
        assembly {
            codeSize := extcodesize(assetAddr)
        }

        if (codeSize == 0) {
            console2.log("  [ERROR] No contract deployed at this address");
        } else {
            console2.log("  [INFO] Contract exists (", codeSize, "bytes)");

            try IERC20Symbol(asset.assetAddress).symbol{ gas: 100_000 }() returns (string memory symbol) {
                console2.log("  [OK] Symbol:", symbol);
            } catch Error(string memory reason) {
                console2.log("  [ERROR] Error calling symbol():", reason);
            } catch (bytes memory) {
                console2.log("  [WARNING] symbol() not available");
            }
        }

        // Try to get oracle description
        console2.log("On-chain Oracle Description:");
        if (asset.oracle != address(0)) {
            try IOracleDescription(asset.oracle).description() returns (string memory description) {
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

    function _getAssets(uint256 chainId) internal returns (DeployStructs.AssetConfig[] memory) {
        if (chainId == 1) {
            MainnetConfig mainnetConfig = new MainnetConfig();
            return mainnetConfig.getAllAssetConfigs();
        } else if (chainId == 11_155_111) {
            SepoliaConfig sepoliaConfig = new SepoliaConfig();
            return sepoliaConfig.getAllAssetConfigs();
        } else if (chainId == 31_337) {
            AnvilConfig anvilConfig = new AnvilConfig();
            return anvilConfig.getAllAssetConfigs();
        } else {
            revert("Unsupported chain ID");
        }
    }
}
