// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { MonadCoreExternalAddresses } from "./MonadCoreExternalAddresses.sol";

/// @title MonadCoreConfig
/// @notice Every ACL right the PT oracle stack on Aave V3 Monad is given, in one file.
///         Mirror of `EthereumCoreConfig`, which documents the ownership model in full.
library MonadCoreConfig {
    /// @notice Phase 1/2 broadcaster. Fresh key; must equal `$ETH_FROM`.
    /// @dev    Deliberately not the Plasma key: a fresh key per chain, as on Plasma and Ethereum.
    ///         Keeps no rights after phase 1 — every ownership is handed to `LLAMARISK_SAFE`, and
    ///         `_verify` reads back that the deployer holds nothing.
    address internal constant DEPLOYER = 0x766046f0345DB9A2CD7d93E565651933E0cCA4C9;

    /// @notice The LlamaRisk safe, same address as Ethereum and Plasma.
    /// @dev    Reached on this chain the way Plasma reached it on 9745: replay the original
    ///         `createProxyWithNonce` bytes, which reproduces CREATION state (threshold 1, two owners
    ///         outside the final set), then reconfigure with swapOwner x2 and changeThreshold(2).
    ///         Every owner handover below targets it, so `_requireTheSafeIsReady` in phase 1 asserts
    ///         both halves — deployed, and reconfigured — because `validate` is pure and cannot read a
    ///         safe.
    address internal constant LLAMARISK_SAFE = 0x1a0267E9E5929a5914Ae9DbBf23Bc07B14365471;

    /// @notice The safe's signing threshold. Creation state is 1, so phase 1 uses this to refuse a
    ///         safe that exists but still carries the creation configuration.
    uint256 internal constant LLAMARISK_SAFE_THRESHOLD = 2;

    /// @notice The expected owner set, read from the live Plasma safe on 2026-10-02, in `getOwners()`
    ///         order. Two of these replace creation owners that are NOT in this set, so matching
    ///         this list is what distinguishes a reconfigured safe from a freshly replayed one.
    function llamariskSafeOwners() internal pure returns (address[] memory owners) {
        owners = new address[](4);
        owners[0] = 0xb3c2337f50D597e6239cE03f0B0023407Dc6A417;
        owners[1] = 0x560681900Fa88Ea4A2F78C62C4a1aC6F8B8B11cB;
        owners[2] = 0x8811e7DFef1CfFD041A9fd39F7e42D0eEd7eCcC3;
        owners[3] = 0x49cE85E1c55cb5b41b8Da2Db85826E3b63A47E00;
    }

    // RiskOracle (BGD stock) — Ownable, single step.
    address internal constant RISK_ORACLE_OWNER = LLAMARISK_SAFE;
    address internal constant RISK_ORACLE_EXTRA_AUTHORIZED_SENDER = address(0);
    string internal constant RISK_ORACLE_DESCRIPTION = "LlamaRisk PT Risk Oracle (Aave V3 Monad)";

    /// @dev Unsuffixed; `EmaImpliedRateUpdate` deliberately absent (the EMA leg never touches the
    ///      RiskOracle).
    string internal constant TYPE_DISCOUNT = "PendleDiscountRateUpdate";
    string internal constant TYPE_EMODE = "EModeCategoryUpdate";

    // LlamaGuardOracle (EMA) — AccessControl.
    address internal constant EMA_ORACLE_ADMIN = LLAMARISK_SAFE;
    address internal constant EMA_ORACLE_EXTRA_WRITER = address(0);
    string internal constant TYPE_EMA = "EmaImpliedRateUpdate";

    // Router bounds, mirrored from the contract; the config test asserts they stay equal.
    uint64 internal constant ROUTER_MIN_REPORT_AGE_SECONDS = 60;
    uint64 internal constant ROUTER_MAX_BPS = 10_000;
    uint64 internal constant ROUTER_MAX_STEP_OFF = type(uint64).max;

    /// @notice Replay-guard bound for the two agent-bearing routes; the EMA route registers 0.
    uint64 internal constant MAX_REPORT_AGE_SECONDS = 1800;

    /// @notice Sentinel: agent id 0 is a legitimate hub id, so 0 cannot double as unset.
    uint256 internal constant AGENT_ID_UNSET = type(uint256).max;

    // PTParameterRegistry — owner and updater are constructor arguments.
    address internal constant REGISTRY_OWNER = MonadCoreExternalAddresses.AAVE_EXECUTOR;
    address internal constant REGISTRY_UPDATER = LLAMARISK_SAFE;

    // LlamaguardRiskOracleRouter — Ownable2Step + updater + guardian.
    address internal constant ROUTER_OWNER = LLAMARISK_SAFE;
    address internal constant ROUTER_UPDATER = LLAMARISK_SAFE;
    address internal constant ROUTER_GUARDIAN = MonadCoreExternalAddresses.AAVE_PROTOCOL_GUARDIAN;

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

    function riskOracleUpdateTypes() internal pure returns (string[] memory types) {
        types = new string[](2);
        types[0] = TYPE_DISCOUNT;
        types[1] = TYPE_EMODE;
    }

    /// @notice Reverts if the config is not safe to act on; `address(0)` skips the deployer check.
    function validate(address broadcaster) internal view {
        require(block.chainid == MonadCoreExternalAddresses.MONAD_CHAIN_ID, "MonadCoreConfig: not on Monad mainnet");
        require(DEPLOYER != address(0), "MonadCoreConfig: DEPLOYER unset");
        require(LLAMARISK_SAFE != address(0), "MonadCoreConfig: LLAMARISK_SAFE unset");
        require(ROUTER_UPDATER != address(0), "MonadCoreConfig: ROUTER_UPDATER cannot be zero");
        require(ROUTER_OWNER != address(0), "MonadCoreConfig: ROUTER_OWNER cannot be zero");
        require(RISK_ORACLE_OWNER != address(0), "MonadCoreConfig: RISK_ORACLE_OWNER cannot be zero");
        require(broadcaster == address(0) || broadcaster == DEPLOYER, "MonadCoreConfig: broadcaster is not DEPLOYER");
        require(
            MAX_REPORT_AGE_SECONDS >= ROUTER_MIN_REPORT_AGE_SECONDS,
            "MonadCoreConfig: MAX_REPORT_AGE_SECONDS below router minimum"
        );
    }

    /// @notice What phase 3 needs beyond `validate`, checked where it is needed: phases 1 and 2 are
    ///         runnable without the route dependencies, phase 3 is not.
    function validateRouteDependencies() internal pure {
        require(MonadCoreExternalAddresses.CRE_FORWARDER != address(0), "MonadCoreConfig: CRE_FORWARDER unset");
    }

    /// @notice What phase 3 additionally needs: the agent-hub stack.
    function validateAgentDependencies() internal view {
        validateRouteDependencies();
        require(MonadCoreExternalAddresses.AGENT_HUB != address(0), "MonadCoreConfig: AGENT_HUB unset");
        require(
            MonadCoreExternalAddresses.AGENT_HUB.code.length != 0, "MonadCoreConfig: AGENT_HUB has no code on Monad"
        );
        require(
            MonadCoreExternalAddresses.RANGE_VALIDATION_MODULE.code.length != 0,
            "MonadCoreConfig: RANGE_VALIDATION_MODULE has no code on Monad"
        );
    }

    function _singletonOrEmpty(address candidate) private pure returns (address[] memory out) {
        if (candidate == address(0)) return new address[](0);
        out = new address[](1);
        out[0] = candidate;
    }
}
