// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/// @notice Chain id constants and known per-chain addresses. Values left at `address(0)` mean
///         the address is not yet known and must be filled in before broadcasting.
library Addresses {
    uint256 internal constant MAINNET = 1;
    uint256 internal constant SEPOLIA = 11_155_111;
    uint256 internal constant PLASMA = 9745;
    uint256 internal constant MANTLE = 5000;

    // ============================================================================================
    // Mainnet (chainid 1)
    // ============================================================================================

    address internal constant MAINNET_OWNER = address(0); // TODO: Aave governance / LlamaRisk multisig
    address internal constant MAINNET_UPDATER = address(0); // TODO: LlamaRisk updater multisig

    // ============================================================================================
    // Sepolia (chainid 11155111)
    // ============================================================================================

    address internal constant SEPOLIA_OWNER = address(0); // defaulted to deployer in DeploySepolia
    address internal constant SEPOLIA_UPDATER = address(0); // defaulted to deployer in DeploySepolia

    // ============================================================================================
    // Plasma (chainid 9745)
    // ============================================================================================

    // Shadow deployment: single LLR hot wallet is owner = updater = deployer = CRE author.
    address internal constant PLASMA_STAGING_OWNER = 0x23ec16308e9C761E89d1D745D3380fBF1fBc21A7;
    address internal constant PLASMA_STAGING_UPDATER = 0x23ec16308e9C761E89d1D745D3380fBF1fBc21A7;

    // PT EMA oracle pipeline (see contracts/script/config/PTEmaConfig.sol).

    /// @notice Plasma PT market the EMA oracle publishes updates for.
    ///         Pendle market with PT expiry 2026-06-18; underlying token
    ///         `0x211cc4dd073734da055fbf44a2b4667d5e5fe5d2`. See
    ///         `docs/reference/phase1-implementation-plan.md` ("Resolved live market
    ///         metadata") for the full PT/YT/SY bundle.
    address internal constant PLASMA_STAGING_PT_EMA_MARKET = 0x30559E3d35e33AB69399a3fe9F383d32bd3c016E;

    /// @dev The Chainlink CRE forwarder address authorized to call onReport on
    ///      the LlamaGuardOracleProxy. Must be set before a Plasma broadcast
    ///      or `PTEmaDeployer.deploy` reverts.
    address internal constant PLASMA_STAGING_PT_EMA_WORKFLOW_FORWARDER = address(0); // TODO

    /// @dev The expected CRE workflow author. Shadow: the single LLR hot wallet.
    address internal constant PLASMA_STAGING_PT_EMA_WORKFLOW_AUTHOR = 0x23ec16308e9C761E89d1D745D3380fBF1fBc21A7;

    /// @dev The expected CRE workflow name (bytes10). Must be set before a
    ///      Plasma broadcast.
    bytes10 internal constant PLASMA_STAGING_PT_EMA_WORKFLOW_NAME = bytes10(0); // TODO

    /// @dev Placeholder for the CRE workflow ID. NOT enforced by
    ///      `PTEmaDeployer` — the receiver-proxy seeds
    ///      `workflowConfigs[bytes32(0)]` with `isActive=true`, and the owner
    ///      is expected to call `setWorkflowConfig` post-deploy with the real
    ///      `(workflowId, forwarder, author, name)` tuple once the CRE
    ///      workflow has been registered. Treat the value below as a default
    ///      seed, not a production constant.
    bytes32 internal constant PLASMA_STAGING_PT_EMA_WORKFLOW_ID = bytes32(0); // PLACEHOLDER — replace post CRE
    // workflow
    // registration

    // ============================================================================================
    // Mantle (chainid 5000)
    // ============================================================================================

    address internal constant MANTLE_OWNER = address(0); // TODO
    address internal constant MANTLE_UPDATER = address(0); // TODO
}
