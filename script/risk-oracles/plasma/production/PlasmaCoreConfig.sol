// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { PlasmaCoreExternalAddresses } from "./PlasmaCoreExternalAddresses.sol";

/// @title PlasmaCoreConfig
/// @notice Every ACL right the phase 1 contracts of the PT oracle stack on Aave V3 Plasma are
///         given, in one file. The deploy script reads this library and nothing else: no address is
///         hardcoded inline in a script and no ACL value comes from an env var, so a review of this
///         file is a review of the whole permission surface.
/// @dev    Mirror of `EthereumCoreConfig`; the ownership model and the deployer-owned-Router trade
///         are documented there and hold unchanged here.
///
///         What differs on Plasma: the LlamaRisk operations safe does not exist on this chain yet.
///         Every ownership slot below that names it is therefore `address(0)`, and `validate()`
///         refuses to run until the safe is deployed and the constant filled. Deploying phase 1
///         before the safe exists would strand the RiskOracle behind an irreversible single-step
///         transfer to a mistyped or absent owner.
library PlasmaCoreConfig {
    // ============================================================================================
    // Principals
    // ============================================================================================

    /// @notice The EOA that broadcasts phase 1 and phase 2. Temporary owner of the RiskOracle and
    ///         the Router between construction and handover, and holds nothing once both complete.
    /// @dev    Fresh key, never used for testing; the shadow operator EOA `0xA99f…460D` is
    ///         deliberately not reused. Must equal `$ETH_FROM` or the script reverts rather than
    ///         deploy a stack the intended deployer cannot hand over.
    address internal constant DEPLOYER = 0xE16a376AB81D57f15a4E30E353C901e8BA53F610;

    /// @notice The LlamaRisk operations multisig, same address as Ethereum production: recreated
    ///         on chain 9745 via the CREATE2 replay of its original creation (SafeToL2Setup, so it
    ///         runs the L2 singleton here).
    /// @dev    A replay reproduces the CREATION state, not Ethereum's current state: the Plasma
    ///         safe starts at threshold 1 with the original owner set, two of whom were since
    ///         swapped out on Ethereum. Before phase 1 runs, reconfigure it to match Ethereum
    ///         (swapOwner x2, changeThreshold to 2) and read both back onchain.
    address internal constant LLAMARISK_SAFE = 0x1a0267E9E5929a5914Ae9DbBf23Bc07B14365471;

    // ============================================================================================
    // RiskOracle (BGD stock) — Ownable, single step
    // ============================================================================================

    /// @notice Manages authorized senders and update types. Reached by handover, not construction.
    address internal constant RISK_ORACLE_OWNER = LLAMARISK_SAFE;

    /// @notice Break-glass sender authorized alongside the Router, or `address(0)` for none.
    address internal constant RISK_ORACLE_EXTRA_AUTHORIZED_SENDER = address(0);

    string internal constant RISK_ORACLE_DESCRIPTION = "LlamaRisk PT Risk Oracle (Aave V3 Plasma)";

    /// @notice The update types the RiskOracle is constructed with.
    /// @dev    Unsuffixed, matching what the workflows already publish and what the AIP constructs
    ///         the agents with (empty `updateTypeSuffix`), so all three layers agree by default.
    ///         `EmaImpliedRateUpdate` is deliberately absent: the EMA leg writes to the
    ///         `LlamaGuardOracle` and never touches the RiskOracle.
    string internal constant TYPE_DISCOUNT = "PendleDiscountRateUpdate";
    string internal constant TYPE_EMODE = "EModeCategoryUpdate";

    // ============================================================================================
    // LlamaGuardOracle (EMA) — AccessControl
    // ============================================================================================

    /// @notice Receives `DEFAULT_ADMIN_ROLE`: manages update types, authorized markets, writers and
    ///         `setMaxPriceDeviation`.
    address internal constant EMA_ORACLE_ADMIN = LLAMARISK_SAFE;

    /// @notice Extra `WRITER_ROLE` holder alongside the Router, or `address(0)` for none.
    address internal constant EMA_ORACLE_EXTRA_WRITER = address(0);

    /// @notice The single update type every PT EMA oracle carries.
    string internal constant TYPE_EMA = "EmaImpliedRateUpdate";

    // ============================================================================================
    // Router bounds and route policy
    // ============================================================================================

    /// @dev Mirrors of `LlamaguardRiskOracleRouter` bounds, asserted against the contract's own
    ///      values by the config test so a bound change fails the suite instead of silently
    ///      loosening this file's validation.
    uint64 internal constant ROUTER_MIN_REPORT_AGE_SECONDS = 60;
    uint64 internal constant ROUTER_MAX_BPS = 10_000;
    uint64 internal constant ROUTER_MAX_STEP_OFF = type(uint64).max;

    /// @notice Replay-guard age bound for the two agent-bearing routes. Both workflows send the
    ///         signed-timestamp envelope, so this must be nonzero and at least the Router minimum.
    ///         The EMA route is registered at 0, because its write path does not envelope.
    uint64 internal constant MAX_REPORT_AGE_SECONDS = 1800;

    /// @notice Sentinel for "no agent id recorded yet". Agent id 0 is a legitimate hub id, so 0
    ///         cannot double as unset.
    uint256 internal constant AGENT_ID_UNSET = type(uint256).max;

    // ============================================================================================
    // PTParameterRegistry — Ownable + updater, both constructor arguments
    // ============================================================================================

    /// @notice Owner: rotates the updater, and nothing else. Aave governance, so every future
    ///         `setUpdater` on this registry costs an AIP.
    address internal constant REGISTRY_OWNER = PlasmaCoreExternalAddresses.AAVE_EXECUTOR;

    /// @notice Updater: the entire write surface, including `setPtMarketParams`.
    address internal constant REGISTRY_UPDATER = LLAMARISK_SAFE;

    // ============================================================================================
    // LlamaguardRiskOracleRouter — Ownable2Step + updater + guardian
    // ============================================================================================

    /// @notice Owner: adds and removes routes, rebinds oracles and hubs, unpauses. Reached by a
    ///         two-step handover, so it is pending until the safe calls `acceptOwnership`.
    address internal constant ROUTER_OWNER = LLAMARISK_SAFE;

    /// @notice Updater: per-route throttles, agent ids and enable flags. Cannot be the zero address.
    address internal constant ROUTER_UPDATER = LLAMARISK_SAFE;

    /// @notice Guardian: `pause` only. The Aave protocol guardian on Plasma rather than our own
    ///         safe, so governance holds a kill switch on this stack that costs no proposal.
    address internal constant ROUTER_GUARDIAN = PlasmaCoreExternalAddresses.AAVE_PROTOCOL_GUARDIAN;

    // ============================================================================================
    // Derived views
    // ============================================================================================

    /// @notice The full set of ACL principals the deploy script applies.
    struct Acl {
        address riskOracleOwner;
        address emaOracleAdmin;
        address registryOwner;
        address registryUpdater;
        address routerOwner;
        address routerUpdater;
        address routerGuardian;
        address[] extraRiskOracleSenders;
        address[] extraEmaOracleWriters;
    }

    /// @notice The production ACL assignment.
    function acl() internal pure returns (Acl memory) {
        return Acl({
            riskOracleOwner: RISK_ORACLE_OWNER,
            emaOracleAdmin: EMA_ORACLE_ADMIN,
            registryOwner: REGISTRY_OWNER,
            registryUpdater: REGISTRY_UPDATER,
            routerOwner: ROUTER_OWNER,
            routerUpdater: ROUTER_UPDATER,
            routerGuardian: ROUTER_GUARDIAN,
            extraRiskOracleSenders: _singletonOrEmpty(RISK_ORACLE_EXTRA_AUTHORIZED_SENDER),
            extraEmaOracleWriters: _singletonOrEmpty(EMA_ORACLE_EXTRA_WRITER)
        });
    }

    /// @notice The update types the RiskOracle is constructed with, in construction order.
    function riskOracleUpdateTypes() internal pure returns (string[] memory types) {
        types = new string[](2);
        types[0] = TYPE_DISCOUNT;
        types[1] = TYPE_EMODE;
    }

    /// @notice Reverts if the config is not safe to act on. Called before anything is deployed, so
    ///         a bad principal fails before the first transaction rather than after a half-deployed
    ///         stack.
    /// @param broadcaster The account the script's calls originate from, or `address(0)` to skip
    ///        the deployer check for a script that broadcasts nothing.
    function validate(address broadcaster) internal view {
        require(
            block.chainid == PlasmaCoreExternalAddresses.PLASMA_CHAIN_ID, "PlasmaCoreConfig: not on Plasma mainnet"
        );
        require(DEPLOYER != address(0), "PlasmaCoreConfig: DEPLOYER unset");
        require(LLAMARISK_SAFE != address(0), "PlasmaCoreConfig: LLAMARISK_SAFE unset, deploy the safe on Plasma first");
        require(ROUTER_UPDATER != address(0), "PlasmaCoreConfig: ROUTER_UPDATER cannot be zero");
        require(ROUTER_OWNER != address(0), "PlasmaCoreConfig: ROUTER_OWNER cannot be zero");
        require(RISK_ORACLE_OWNER != address(0), "PlasmaCoreConfig: RISK_ORACLE_OWNER cannot be zero");
        require(broadcaster == address(0) || broadcaster == DEPLOYER, "PlasmaCoreConfig: broadcaster is not DEPLOYER");
        require(
            MAX_REPORT_AGE_SECONDS >= ROUTER_MIN_REPORT_AGE_SECONDS,
            "PlasmaCoreConfig: MAX_REPORT_AGE_SECONDS below router minimum"
        );
    }

    function _singletonOrEmpty(address candidate) private pure returns (address[] memory out) {
        if (candidate == address(0)) return new address[](0);
        out = new address[](1);
        out[0] = candidate;
    }
}
