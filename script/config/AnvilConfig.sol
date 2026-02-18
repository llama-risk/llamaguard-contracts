// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { DeployStructs } from "./DeployStructs.sol";
import { Addresses } from "./Addresses.sol";

/// @title AnvilConfig
/// @notice Configuration for local Anvil testing
/// @dev Same interface as MainnetConfig/SepoliaConfig
contract AnvilConfig {
    error UnknownAsset();

    // ═══════════════════════════════════════════════════════════════════════════
    // ORACLE CONFIGURATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Get all oracle deployment configs for Anvil
    function getAllOracleConfigs() public pure returns (DeployStructs.OracleDeploymentConfig[] memory configs) {
        configs = new DeployStructs.OracleDeploymentConfig[](2);

        string[] memory updateTypes0 = new string[](1);
        updateTypes0[0] = "boundedNAV";
        address[] memory emptyMarkets = new address[](0);

        configs[0] = DeployStructs.OracleDeploymentConfig({
            oracle: DeployStructs.OracleConfig({
                name: "TEST1",
                decimals: 8,
                description: "LlamaGuard Risk Oracle 1 (Local)",
                version: 1,
                updateTypes: updateTypes0,
                authorizedMarkets: emptyMarkets
            }),
            proxy: DeployStructs.ProxyConfig({
                workflowId: keccak256("test-workflow-1"),
                expectedForwarder: Addresses.ANVIL_ACCOUNT_0,
                expectedAuthor: Addresses.ANVIL_ACCOUNT_0,
                expectedWorkflowName: bytes10("testwork01"),
                description: "LlamaGuard Oracle Proxy 1 (Local)"
            }),
            pendingOwner: address(0)
        });

        string[] memory updateTypes1 = new string[](1);
        updateTypes1[0] = "boundedNAV";

        configs[1] = DeployStructs.OracleDeploymentConfig({
            oracle: DeployStructs.OracleConfig({
                name: "TEST2",
                decimals: 18,
                description: "LlamaGuard Risk Oracle 2 (Local)",
                version: 1,
                updateTypes: updateTypes1,
                authorizedMarkets: emptyMarkets
            }),
            proxy: DeployStructs.ProxyConfig({
                workflowId: keccak256("test-workflow-2"),
                expectedForwarder: Addresses.ANVIL_ACCOUNT_1,
                expectedAuthor: Addresses.ANVIL_ACCOUNT_1,
                expectedWorkflowName: bytes10("testwork02"),
                description: "LlamaGuard Oracle Proxy 2 (Local)"
            }),
            pendingOwner: address(0)
        });
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ASSET CONFIGS (ParameterRegistry)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Get all asset configs for Anvil ParameterRegistry
    function getAllAssetConfigs() public pure returns (DeployStructs.AssetConfig[] memory assets) {
        assets = new DeployStructs.AssetConfig[](3);

        assets[0] = DeployStructs.AssetConfig({
            assetAddress: 0x5FbDB2315678afecb367f032d93F642f64180aa3,
            assetName: "Mock USDC",
            oracle: 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512,
            maxExpectedApy: 1200,
            upperBoundTolerance: 100,
            lowerBoundTolerance: 100,
            maxDiscount: 200,
            lookbackWindowSize: 24,
            isUpperBoundEnabled: true,
            isLowerBoundEnabled: true,
            isActionTakingEnabled: true
        });

        assets[1] = DeployStructs.AssetConfig({
            assetAddress: 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0,
            assetName: "Mock WETH",
            oracle: 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9,
            maxExpectedApy: 5000,
            upperBoundTolerance: 250,
            lowerBoundTolerance: 200,
            maxDiscount: 250,
            lookbackWindowSize: 72,
            isUpperBoundEnabled: true,
            isLowerBoundEnabled: false,
            isActionTakingEnabled: true
        });

        assets[2] = DeployStructs.AssetConfig({
            assetAddress: 0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9,
            assetName: "Mock Stable",
            oracle: 0x5FC8d32690cc91D4c39d9d3abcBD16989F875707,
            maxExpectedApy: 300,
            upperBoundTolerance: 25,
            lowerBoundTolerance: 25,
            maxDiscount: 50,
            lookbackWindowSize: 12,
            isUpperBoundEnabled: true,
            isLowerBoundEnabled: true,
            isActionTakingEnabled: false
        });
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DEPLOYMENT OWNERSHIP
    // ═══════════════════════════════════════════════════════════════════════════

    function getDeployerAddress() public pure returns (address) {
        return Addresses.ANVIL_ACCOUNT_0;
    }
}
