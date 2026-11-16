// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/// @title PlasmaCoreConfig
/// @notice Who holds what on the Plasma PT oracle stack. The core (risk oracle, registry, router)
///         and both agents are already live; this repo only adds per-asset phases on top of them.
library PlasmaCoreConfig {
    uint256 internal constant PLASMA_CHAIN_ID = 9745;

    /// @notice The key that deployed the live Plasma core. Phase 2 broadcaster; must equal `$ETH_FROM`.
    address internal constant DEPLOYER = 0xE16a376AB81D57f15a4E30E353C901e8BA53F610;

    /// @notice The LlamaRisk safe, same address as Ethereum and Monad.
    address internal constant LLAMARISK_SAFE = 0x1a0267E9E5929a5914Ae9DbBf23Bc07B14365471;

    // LlamaGuardOracle (EMA) — AccessControl.
    address internal constant EMA_ORACLE_ADMIN = LLAMARISK_SAFE;
    address internal constant EMA_ORACLE_EXTRA_WRITER = address(0);
    string internal constant TYPE_EMA = "EmaImpliedRateUpdate";

    // PTParameterRegistry — updater set at deploy.
    address internal constant REGISTRY_UPDATER = LLAMARISK_SAFE;

    struct Acl {
        address emaOracleAdmin;
        address registryUpdater;
        address[] extraEmaOracleWriters;
    }

    function acl() internal pure returns (Acl memory) {
        return Acl({
            emaOracleAdmin: EMA_ORACLE_ADMIN,
            registryUpdater: REGISTRY_UPDATER,
            extraEmaOracleWriters: _singletonOrEmpty(EMA_ORACLE_EXTRA_WRITER)
        });
    }

    /// @notice Reverts if the config is not safe to act on; `address(0)` skips the deployer check.
    function validate(address broadcaster) internal view {
        require(block.chainid == PLASMA_CHAIN_ID, "PlasmaCoreConfig: not on Plasma mainnet");
        require(broadcaster == address(0) || broadcaster == DEPLOYER, "PlasmaCoreConfig: broadcaster is not DEPLOYER");
    }

    function _singletonOrEmpty(address candidate) private pure returns (address[] memory out) {
        if (candidate == address(0)) return new address[](0);
        out = new address[](1);
        out[0] = candidate;
    }
}
