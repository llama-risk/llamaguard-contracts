// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { XLayerCoreConfig } from "./XLayerCoreConfig.sol";

/// @title XLayerCoreDeployed
/// @notice What each phase produced; the next phase reads its inputs from here, never from env.
///         Unset means zero and the scripts revert on it. The agent ids use a sentinel because 0
///         is a legitimate hub id.
/// @dev    Each phase prints `OUTPUT:` lines; paste them here and commit before running the next
///         phase, so every recorded address is one read back onchain.
library XLayerCoreDeployed {
    // Phase 1. RISK_ORACLE is also the AIP payload's LLAMARISK_RISK_ORACLE.
    address internal constant RISK_ORACLE = address(0);
    address internal constant PT_PARAMETER_REGISTRY = address(0);
    address internal constant ROUTER = address(0);

    // Phase 2.
    address internal constant EMA_ORACLE_PT_USDG_25FEB2027 = address(0);

    // aave-risk-agents `DeployXLayer`, 2026-10-15, blocks 73,330,738 and 73,330,741, verified on
    // OKLink and read back onchain (hub, range module and pool). The AIP registers them and assigns
    // the ids below; the hub's `getAgentCount()` reads 0, so 0 and 1 are expected.
    address internal constant DISCOUNT_RATE_AGENT = 0xb00251C67dB290D0AD779903bfFeB092DAE76fFa;
    address internal constant EMODE_AGENT = 0x19ae7c91dfd35a4515595cEd305d2102C3b1B02D;
    uint256 internal constant DISCOUNT_AGENT_ID = XLayerCoreConfig.AGENT_ID_UNSET;
    uint256 internal constant EMODE_AGENT_ID = XLayerCoreConfig.AGENT_ID_UNSET;

    // `cre workflow hash --target=xlayer-production` output, owner the Aave CRE org safe. Editing a
    // config after this point mints a new id, and the discount and risk-params ids depend on the
    // hub agent ids the AIP assigns, so they are re-hashed if the AIP lands different ones.
    bytes32 internal constant EMA_WORKFLOW_ID = bytes32(0);
    bytes32 internal constant DISCOUNT_WORKFLOW_ID = bytes32(0);
    bytes32 internal constant RISK_PARAMS_WORKFLOW_ID = bytes32(0);
}
