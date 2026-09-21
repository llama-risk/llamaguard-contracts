// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { PlasmaCoreConfig } from "./PlasmaCoreConfig.sol";

/// @title PlasmaCoreDeployed
/// @notice What each phase produced; the next phase reads its inputs from here, never from env.
///         Unset means zero and the scripts revert on it. The agent ids use a sentinel because 0
///         is a legitimate hub id.
library PlasmaCoreDeployed {
    // Phase 1, broadcast 2026-09-21, read back onchain. RISK_ORACLE is also the AIP payload's
    // LLAMARISK_RISK_ORACLE.
    address internal constant RISK_ORACLE = 0x4f240E3825e7FD6D834EEb861b1539dF0b43BfD0;
    address internal constant PT_PARAMETER_REGISTRY = 0xED34a5374FeaaD8Ead024023d2Fc3b844bb9Bb47;
    address internal constant ROUTER = 0xaC8690DE68dcB7068805c0C631004E9894FAFbe0;

    // Phase 2.
    address internal constant EMA_ORACLE_PT_SUSDE_22OCT2026 = address(0);

    // The AIP's output, read back off Aave's hub after the payload executes.
    address internal constant DISCOUNT_RATE_AGENT = address(0);
    address internal constant EMODE_AGENT = address(0);
    uint256 internal constant DISCOUNT_AGENT_ID = PlasmaCoreConfig.AGENT_ID_UNSET;
    uint256 internal constant EMODE_AGENT_ID = PlasmaCoreConfig.AGENT_ID_UNSET;

    // `cre workflow deploy` output. Editing a config after this point mints a new id.
    bytes32 internal constant EMA_WORKFLOW_ID = bytes32(0);
    bytes32 internal constant DISCOUNT_WORKFLOW_ID = bytes32(0);
    bytes32 internal constant RISK_PARAMS_WORKFLOW_ID = bytes32(0);
}
