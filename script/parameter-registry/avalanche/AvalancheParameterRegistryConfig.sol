// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { GovernanceV3Avalanche } from "aave-address-book/GovernanceV3Avalanche.sol";

interface ISafeOwners {
    function getThreshold() external view returns (uint256);
    function getOwners() external view returns (address[] memory);
    function isOwner(address owner) external view returns (bool);
}

/// @title AvalancheParameterRegistryConfig
/// @notice The owner, the updater and the discount limit of the NAV `AvalancheParameterRegistry`. The constructor sets
///         both roles.
library AvalancheParameterRegistryConfig {
    uint256 internal constant AVALANCHE_CHAIN_ID = 43_114;

    /// @notice Owner: the Aave governance executor. The owner can only rotate the updater.
    address internal constant REGISTRY_OWNER = GovernanceV3Avalanche.EXECUTOR_LVL_1;

    /// @notice Updater: the Avalanche Risk Council safe. The updater writes all asset parameters.
    address internal constant REGISTRY_UPDATER = 0xCa66149425E7DC8f81276F6D80C4b486B9503D1a;

    /// @notice Maximum `maxDiscount` in BPS that the deployed registry must enforce.
    uint32 internal constant MAX_DISCOUNT_LIMIT = 1000;

    /// @notice Signers and threshold that the updater safe must have.
    address internal constant LLAMARISK_SIGNER = 0xb291232F480F41c75802C4a60F1D2AC03404Afef;
    address internal constant COSIGNER = 0x606dC57cd166643760E049609bfd1D8a698D3bAc;
    uint256 internal constant REGISTRY_UPDATER_SIGNERS = 2;
    uint256 internal constant REGISTRY_UPDATER_THRESHOLD = 2;

    /// @dev Checks both roles against live state before broadcast.
    function validate() internal view {
        require(block.chainid == AVALANCHE_CHAIN_ID, "AvalancheParameterRegistryConfig: not on Avalanche C-Chain");
        require(REGISTRY_OWNER.code.length > 0, "AvalancheParameterRegistryConfig: owner has no code");
        require(REGISTRY_UPDATER.code.length > 0, "AvalancheParameterRegistryConfig: updater has no code");

        ISafeOwners council = ISafeOwners(REGISTRY_UPDATER);
        require(
            council.getThreshold() == REGISTRY_UPDATER_THRESHOLD,
            "AvalancheParameterRegistryConfig: updater threshold changed"
        );
        require(
            council.getOwners().length == REGISTRY_UPDATER_SIGNERS,
            "AvalancheParameterRegistryConfig: updater signer count changed"
        );
        require(council.isOwner(LLAMARISK_SIGNER), "AvalancheParameterRegistryConfig: LlamaRisk signer missing");
        require(council.isOwner(COSIGNER), "AvalancheParameterRegistryConfig: cosigner missing");
    }
}
