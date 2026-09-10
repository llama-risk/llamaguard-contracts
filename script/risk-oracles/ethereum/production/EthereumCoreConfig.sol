// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { EthereumCoreExternalAddresses } from "./EthereumCoreExternalAddresses.sol";

/// @title EthereumCoreConfig
/// @notice Every ACL right the phase 1 contracts of the PT oracle stack on Aave V3 Ethereum Core
///         are given, in one file. The deploy script reads this library and nothing else: no address
///         is hardcoded inline in a script and no ACL value comes from an env var, so a review of
///         this file is a review of the whole permission surface.
/// @dev    Chain scoped, and scoped to phase 1. Per-asset values and the agent, EMA and route
///         policy arrive with the phases that apply them.
///
///         Ownership model, because it drives what the script may do:
///           - `PTParameterRegistry` takes its owner and updater as constructor arguments, so it
///             lands in final ownership at birth. The deployer never owns it.
///           - `RiskOracle` is `Ownable(msg.sender)`, single step. Phase 1 authorises the Router and
///             then transfers outright. The transfer is immediate and irreversible, so a mistyped
///             owner bricks the contract.
///           - `LlamaguardRiskOracleRouter` is `Ownable2Step`. Phase 1 constructs it owned by the
///             DEPLOYER so that `setUpdater` and `setGuardian` can be broadcast rather than signed,
///             then starts the handover to `ROUTER_OWNER`. The deployer therefore remains Router
///             owner until the safe sends `acceptOwnership`, which is the one call phase 1 cannot
///             make and the only entry in its safe batch.
///
///         That last point is a deliberate trade and worth stating plainly. Constructing the Router
///         owned by the safe would mean the deployer never holds it, but `setUpdater` and
///         `setGuardian` are `onlyOwner`, so both would become safe transactions. Constructing it
///         owned by the deployer collapses those into the broadcast and leaves exactly one signature
///         to collect. The cost is a window, bounded by how long that signature takes, in which the
///         deploy key can add a route. Nothing is at risk inside it: no workflow exists yet, so a
///         route added there has no author to accept reports from, and the safe can remove it.
library EthereumCoreConfig {
    // ============================================================================================
    // Principals
    // ============================================================================================

    /// @notice The EOA that broadcasts phase 1. Temporary owner of the RiskOracle and the Router
    ///         between construction and handover, and holds nothing once both complete.
    /// @dev    Must equal `$ETH_FROM` (or the account derived from `$MNEMONIC`) or the script reverts
    ///         rather than deploy a stack the intended deployer cannot hand over.
    address internal constant DEPLOYER = 0x987e720716263d75eaDB1806DB90Ad2Cc4210EEA;

    /// @notice The LlamaRisk operations multisig. Operational owner of the whole stack once the
    ///         handovers complete.
    address internal constant LLAMARISK_SAFE = 0x1a0267E9E5929a5914Ae9DbBf23Bc07B14365471;

    // ============================================================================================
    // RiskOracle (BGD stock) — Ownable, single step
    // ============================================================================================

    /// @notice Manages authorized senders and update types. Reached by handover, not construction.
    address internal constant RISK_ORACLE_OWNER = LLAMARISK_SAFE;

    /// @notice Break-glass sender authorized alongside the Router, or `address(0)` for none. The
    ///         Router is authorized unconditionally by phase 1; this is the only other way anything
    ///         can publish.
    address internal constant RISK_ORACLE_EXTRA_AUTHORIZED_SENDER = address(0);

    string internal constant RISK_ORACLE_DESCRIPTION = "LlamaRisk PT Risk Oracle (Aave V3 Ethereum Core)";

    /// @notice The update types the RiskOracle is constructed with.
    /// @dev    Kept as literals because `string.concat` is not usable in a constant.
    ///
    ///         Unsuffixed, which is what makes the offchain side need no change: the workflows
    ///         already publish `PendleDiscountRateUpdate` and `EModeCategoryUpdate`. The AIP
    ///         constructs both agents with an empty `updateTypeSuffix`, so all three layers agree by
    ///         default rather than by configuration. Nothing here can enforce that, because the
    ///         agents are the payload's to deploy, so phase 3 reads `getUpdateType` back off the hub
    ///         and compares against these two before it will wire a route.
    ///
    ///         `EmaImpliedRateUpdate` is deliberately absent: the EMA leg writes to the
    ///         `LlamaGuardOracle` through `updateLatestRiskRoundData` and never touches the
    ///         RiskOracle, so registering it here would be a type nothing publishes. If that ever
    ///         changes, `addUpdateType` is an owner call on the safe, not an AIP.
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

    /// @notice The single update type every PT EMA oracle carries. Consumed by the EMA oracle and
    ///         the two reading workflows, never by an agent, which is why it is absent from the
    ///         RiskOracle's own types.
    string internal constant TYPE_EMA = "EmaImpliedRateUpdate";

    // ============================================================================================
    // Router bounds and route policy
    // ============================================================================================

    /// @dev Mirrors of `LlamaguardRiskOracleRouter` bounds. The Router declares them `internal`, so
    ///      they cannot be read through the contract type from here. `EthereumCoreConfig.t.sol`
    ///      asserts these stay equal to the Router's own values, so a bound change in the contract
    ///      fails the suite instead of silently loosening this file's validation.
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
    /// @dev    Set directly by `Ownable(_owner)` rather than through a two-step transfer, so no
    ///         `acceptOwnership` call is needed in the payload.
    address internal constant REGISTRY_OWNER = EthereumCoreExternalAddresses.AAVE_EXECUTOR;

    /// @notice Updater: the entire write surface, including `setPtMarketParams`. The safe rather
    ///         than a hot wallet because rotating it costs an AIP, and safe signers can be rotated
    ///         internally where a hot wallet key cannot.
    address internal constant REGISTRY_UPDATER = LLAMARISK_SAFE;

    // ============================================================================================
    // LlamaguardRiskOracleRouter — Ownable2Step + updater + guardian
    // ============================================================================================

    /// @notice Owner: adds and removes routes, rebinds oracles and hubs, unpauses. Reached by a
    ///         two-step handover, so it is pending until the safe calls `acceptOwnership`.
    address internal constant ROUTER_OWNER = LLAMARISK_SAFE;

    /// @notice Updater: per-route throttles, agent ids and enable flags. Cannot be the zero address.
    address internal constant ROUTER_UPDATER = LLAMARISK_SAFE;

    /// @notice Guardian: `pause` only. The Aave protocol emergency multisig rather than our own
    ///         safe, so governance holds a kill switch on this stack that costs no proposal.
    /// @dev    `unpause` is `onlyOwner`, so this address can stop the stack and cannot restart it.
    ///         Setting it to our safe, which already owns and updates the Router, would make the
    ///         slot dead weight; setting it to a LlamaRisk hot key would buy faster reaction at the
    ///         cost of a key that can halt production alone. See the note on the constant itself.
    ///
    ///         `setGuardian` has no zero check, so this slot is legitimately optional and can be
    ///         rotated by the owner at any time with no redeploy and no AIP.
    address internal constant ROUTER_GUARDIAN = EthereumCoreExternalAddresses.AAVE_PROTOCOL_GUARDIAN;

    // ============================================================================================
    // Derived views
    // ============================================================================================

    /// @notice The full set of ACL principals the deploy script applies.
    /// @dev    Passed as a struct rather than read constant by constant inside the script, so the
    ///         wiring can be exercised in tests against principals other than the production ones.
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

    /// @notice Reverts if the config is not safe to act on. Called before anything is deployed, so a
    ///         bad principal fails before the first transaction rather than after a half-deployed
    ///         stack.
    /// @param broadcaster The account the script's calls originate from, or `address(0)` to skip the
    ///        deployer check for a script that broadcasts nothing.
    function validate(address broadcaster) internal view {
        require(
            block.chainid == EthereumCoreExternalAddresses.ETHEREUM_CHAIN_ID,
            "EthereumCoreConfig: not on Ethereum mainnet"
        );
        require(DEPLOYER != address(0), "EthereumCoreConfig: DEPLOYER unset");
        require(LLAMARISK_SAFE != address(0), "EthereumCoreConfig: LLAMARISK_SAFE unset");
        require(ROUTER_UPDATER != address(0), "EthereumCoreConfig: ROUTER_UPDATER cannot be zero");
        require(ROUTER_OWNER != address(0), "EthereumCoreConfig: ROUTER_OWNER cannot be zero");
        require(RISK_ORACLE_OWNER != address(0), "EthereumCoreConfig: RISK_ORACLE_OWNER cannot be zero");
        require(broadcaster == address(0) || broadcaster == DEPLOYER, "EthereumCoreConfig: broadcaster is not DEPLOYER");
        require(
            MAX_REPORT_AGE_SECONDS >= ROUTER_MIN_REPORT_AGE_SECONDS,
            "EthereumCoreConfig: MAX_REPORT_AGE_SECONDS below router minimum"
        );
    }

    function _singletonOrEmpty(address candidate) private pure returns (address[] memory out) {
        if (candidate == address(0)) return new address[](0);
        out = new address[](1);
        out[0] = candidate;
    }
}
