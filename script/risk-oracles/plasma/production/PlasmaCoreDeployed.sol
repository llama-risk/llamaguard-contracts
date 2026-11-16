// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/// @title PlasmaCoreDeployed
/// @notice The live Plasma stack, plus what each per-asset phase produced. Unset means zero and
///         the scripts revert on it.
/// @dev    Literals because the pinned `aave-address-book` has no LlamaRisk entries for Plasma.
///         The fork test reads each one back.
library PlasmaCoreDeployed {
    // Core, deployed by `PlasmaCoreConfig.DEPLOYER` at nonces 0-2, owned by the safe.
    address internal constant RISK_ORACLE = 0x4f240E3825e7FD6D834EEb861b1539dF0b43BfD0;
    address internal constant PT_PARAMETER_REGISTRY = 0xED34a5374FeaaD8Ead024023d2Fc3b844bb9Bb47;
    address internal constant ROUTER = 0xaC8690DE68dcB7068805c0C631004E9894FAFbe0;

    // Agents, registered on the hub by the PT-sUSDe-22OCT2026 oracle AIP.
    address internal constant AGENT_HUB = 0x5F29ACbFB6de4282bB4DD2017930cDA730eD864D;
    address internal constant DISCOUNT_RATE_AGENT = 0xC0F2BC223262338959732896758a9Fe95d2b4E29;
    address internal constant EMODE_AGENT = 0xBcFaBC3ea806d4755ED3F1eA2C5EAE92706Beb29;
    uint256 internal constant DISCOUNT_AGENT_ID = 2;
    uint256 internal constant EMODE_AGENT_ID = 3;

    // PT-sUSDE-28JAN2027, phase 2.
    address internal constant EMA_ORACLE_PT_sUSDE_28JAN2027 = address(0);
}
