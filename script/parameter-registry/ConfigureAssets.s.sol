// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { ParameterRegistry } from "../../src/ParameterRegistry.sol";
import { BaseScript } from "../Base.s.sol";
import { DeployStructs } from "../config/DeployStructs.sol";
import { MainnetConfig } from "../config/MainnetConfig.sol";
import { SepoliaConfig } from "../config/SepoliaConfig.sol";
import { AnvilConfig } from "../config/AnvilConfig.sol";
import { console2 } from "forge-std/Test.sol";

/// @title ConfigureAssets
/// @notice Configure assets in an existing ParameterRegistry
/// @dev Uses consolidated config files for asset parameters
contract ConfigureAssets is BaseScript {
    /// @notice Configure assets on an existing registry (auto-detects chain)
    /// @param registryAddress The deployed ParameterRegistry address
    function run(address registryAddress) public broadcast {
        require(registryAddress != address(0), "Registry address cannot be zero");

        ParameterRegistry registry = ParameterRegistry(registryAddress);
        require(registry.updater() == broadcaster, "Caller is not the updater");

        console2.log("=========================================");
        console2.log("Configure Assets in ParameterRegistry");
        console2.log("=========================================");
        console2.log("Registry:", registryAddress);
        console2.log("Chain ID:", block.chainid);

        DeployStructs.AssetConfig[] memory assets = _getAssets();

        console2.log("Configuring", assets.length, "assets...");

        for (uint256 i = 0; i < assets.length; ++i) {
            if (assets[i].oracle == address(0)) {
                console2.log("  [SKIP]", assets[i].assetName, "(no oracle)");
                continue;
            }

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
            console2.log("  [OK]", assets[i].assetName);
        }

        console2.log("=========================================");
    }

    function _getAssets() internal returns (DeployStructs.AssetConfig[] memory) {
        if (block.chainid == 1) {
            MainnetConfig mainnetConfig = new MainnetConfig();
            return mainnetConfig.getAllAssetConfigs();
        } else if (block.chainid == 11_155_111) {
            SepoliaConfig sepoliaConfig = new SepoliaConfig();
            return sepoliaConfig.getAllAssetConfigs();
        } else if (block.chainid == 31_337) {
            AnvilConfig anvilConfig = new AnvilConfig();
            return anvilConfig.getAllAssetConfigs();
        } else {
            revert("Unsupported chain ID");
        }
    }
}
