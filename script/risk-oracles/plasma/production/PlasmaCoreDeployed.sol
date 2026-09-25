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

    // Phase 2, broadcast 2026-09-21, roles read back onchain.
    address internal constant EMA_ORACLE_PT_SUSDE_22OCT2026 = 0xfA3187E63d5eEc6189702E24dEAbC82b80853809;

    // Predeployed (ownerless, immutables read back onchain); the AIP registers them. The eMode
    // agent was redeployed 2026-09-22 from aave-dao/aave-risk-agents@dec4cc7, which adds
    // `isolated: KEEP_CURRENT` for the Aave 3.7 config-engine surface; the pre-fix instance
    // 0x3DdA…9ae6 is orphaned (ownerless, never registered). The discount agent does not touch
    // the config engine and stands.
    address internal constant DISCOUNT_RATE_AGENT = 0x8feb86657dbBbB89B7D2D115263D6927Afeb8bd4;
    address internal constant EMODE_AGENT = 0xBcFaBC3ea806d4755ED3F1eA2C5EAE92706Beb29;
    uint256 internal constant DISCOUNT_AGENT_ID = PlasmaCoreConfig.AGENT_ID_UNSET;
    uint256 internal constant EMODE_AGENT_ID = PlasmaCoreConfig.AGENT_ID_UNSET;

    // `cre workflow hash` output at llamaguard-risk-oracles 7078aa7 (main-based; ids reproduced 2026-09-25), owner the Aave CRE org
    // safe. Editing a config after this point mints a new id; the discount and risk-params ids
    // assume hub agent ids 2/3 and are re-hashed if the AIP lands different ones.
    bytes32 internal constant EMA_WORKFLOW_ID = 0x00790e32dcb34cf608476b2115f9f7b23de02cb1c2e041274aa1db0954199081;
    bytes32 internal constant DISCOUNT_WORKFLOW_ID = 0x00ce8ad03725731e4e3b6de2e221ebd592e45ac3e144a466804d2ec3bce460c1;
    bytes32 internal constant RISK_PARAMS_WORKFLOW_ID = 0x0084b8438576585052311606c900c98b540c4c38536af5f99120698e406bf810;
}
