// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { Addresses } from "./Addresses.sol";

/// @notice Per-chain deploy configuration for the PT EMA oracle pipeline.
/// @dev Mirrors the shape of `EthereumConfig.sol` / `PlasmaConfig.sol`. Real
///      addresses live in `Addresses.sol` (placeholders left at `address(0)` /
///      `bytes10(0)` must be filled before broadcasting on Plasma — the
///      `PTEmaDeployer` library enforces this at deploy time).
library PTEmaConfig {
    struct PTEmaDeployConfig {
        uint8 oracleDecimals;
        string oracleDescription;
        uint256 oracleVersion;
        string[] initialUpdateTypes;
        address[] initialAuthorizedMarkets;
        bytes32 emaWorkflowId;
        address emaWorkflowForwarder;
        address emaWorkflowAuthor;
        bytes10 emaWorkflowName;
        string proxyDescription;
        address owner;
    }

    /// @notice The single update type written by the EMA workflow.
    string internal constant UPDATE_TYPE_EMA = "EmaImpliedRateUpdate";

    function getPlasmaConfig() internal pure returns (PTEmaDeployConfig memory cfg) {
        string[] memory updateTypes = new string[](1);
        updateTypes[0] = UPDATE_TYPE_EMA;

        address[] memory markets = new address[](1);
        markets[0] = Addresses.PLASMA_STAGING_PT_EMA_MARKET;

        cfg = PTEmaDeployConfig({
            oracleDecimals: 18,
            oracleDescription: "PT EMA Implied Rate (Pendle)",
            oracleVersion: 1,
            initialUpdateTypes: updateTypes,
            initialAuthorizedMarkets: markets,
            emaWorkflowId: Addresses.PLASMA_STAGING_PT_EMA_WORKFLOW_ID,
            emaWorkflowForwarder: Addresses.PLASMA_STAGING_PT_EMA_WORKFLOW_FORWARDER,
            emaWorkflowAuthor: Addresses.PLASMA_STAGING_PT_EMA_WORKFLOW_AUTHOR,
            emaWorkflowName: Addresses.PLASMA_STAGING_PT_EMA_WORKFLOW_NAME,
            proxyDescription: "PT EMA receiver proxy (Plasma)",
            owner: Addresses.PLASMA_STAGING_OWNER
        });
    }

    /// @notice Sepolia staging config. Uses the deployer as owner and as the
    ///         seed for the workflow params so a dry-run against the public
    ///         Sepolia RPC works without extra envs. The synthesized
    ///         forwarder/author/name addresses are non-zero (to pass the
    ///         `PTEmaDeployer` guards) but obviously useless against a real
    ///         CRE workflow — the receiver-proxy owner must call
    ///         `setWorkflowConfig` with real values before pointing a
    ///         workflow at the staging deploy.
    function getSepoliaConfig(address deployer) internal pure returns (PTEmaDeployConfig memory cfg) {
        string[] memory updateTypes = new string[](1);
        updateTypes[0] = UPDATE_TYPE_EMA;

        // Synthetic market address so the staging deploy never accidentally
        // authorizes a real PT market.
        address[] memory markets = new address[](1);
        markets[0] = address(uint160(uint256(keccak256(abi.encodePacked("pt-ema-sepolia-market", deployer)))));

        cfg = PTEmaDeployConfig({
            oracleDecimals: 18,
            oracleDescription: "PT EMA Implied Rate (Pendle, Sepolia staging)",
            oracleVersion: 1,
            initialUpdateTypes: updateTypes,
            initialAuthorizedMarkets: markets,
            emaWorkflowId: bytes32(uint256(keccak256(abi.encodePacked("pt-ema-sepolia-workflow-id", deployer)))),
            emaWorkflowForwarder: address(
                uint160(uint256(keccak256(abi.encodePacked("pt-ema-sepolia-forwarder", deployer))))
            ),
            emaWorkflowAuthor: address(
                uint160(uint256(keccak256(abi.encodePacked("pt-ema-sepolia-author", deployer))))
            ),
            emaWorkflowName: bytes10(keccak256(abi.encodePacked("pt-ema-sepolia-name", deployer))),
            proxyDescription: "PT EMA receiver proxy (Sepolia staging)",
            owner: deployer
        });
    }
}
