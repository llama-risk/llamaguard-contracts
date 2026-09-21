// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { PlasmaCoreExternalAddresses } from "./PlasmaCoreExternalAddresses.sol";

/// @title PlasmaCoreConfig
/// @notice Every ACL right the PT oracle stack on Aave V3 Plasma is given, in one file.
///         Mirror of `EthereumCoreConfig`, which documents the ownership model in full.
library PlasmaCoreConfig {
    /// @notice Phase 1/2 broadcaster. Fresh key; must equal `$ETH_FROM`.
    address internal constant DEPLOYER = 0xE16a376AB81D57f15a4E30E353C901e8BA53F610;

    /// @notice The LlamaRisk safe, same address as Ethereum, recreated on 9745 via CREATE2 replay.
    /// @dev    Replay reproduces CREATION state (threshold 1, original owners). Reconfigure to
    ///         match Ethereum (swapOwner x2, changeThreshold 2) before phase 1.
    address internal constant LLAMARISK_SAFE = 0x1a0267E9E5929a5914Ae9DbBf23Bc07B14365471;

    // RiskOracle (BGD stock) — Ownable, single step.
    address internal constant RISK_ORACLE_OWNER = LLAMARISK_SAFE;
    address internal constant RISK_ORACLE_EXTRA_AUTHORIZED_SENDER = address(0);
    string internal constant RISK_ORACLE_DESCRIPTION = "LlamaRisk PT Risk Oracle (Aave V3 Plasma)";

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
    address internal constant REGISTRY_OWNER = PlasmaCoreExternalAddresses.AAVE_EXECUTOR;
    address internal constant REGISTRY_UPDATER = LLAMARISK_SAFE;

    // LlamaguardRiskOracleRouter — Ownable2Step + updater + guardian.
    address internal constant ROUTER_OWNER = LLAMARISK_SAFE;
    address internal constant ROUTER_UPDATER = LLAMARISK_SAFE;
    address internal constant ROUTER_GUARDIAN = PlasmaCoreExternalAddresses.AAVE_PROTOCOL_GUARDIAN;

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
        require(
            block.chainid == PlasmaCoreExternalAddresses.PLASMA_CHAIN_ID, "PlasmaCoreConfig: not on Plasma mainnet"
        );
        require(DEPLOYER != address(0), "PlasmaCoreConfig: DEPLOYER unset");
        require(LLAMARISK_SAFE != address(0), "PlasmaCoreConfig: LLAMARISK_SAFE unset");
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
