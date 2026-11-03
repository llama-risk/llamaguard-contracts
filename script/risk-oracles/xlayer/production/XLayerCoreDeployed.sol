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
    // Phase 1, broadcast 2026-10-15 at blocks 73332554-73332571, principals read back onchain.
    // RISK_ORACLE is also the AIP payload's LLAMARISK_RISK_ORACLE.
    address internal constant RISK_ORACLE = 0x3e0C920C2bdDF6DF87f9A39Ea4db9CF65Cec1EDE;
    address internal constant PT_PARAMETER_REGISTRY = 0x101D7eA4D0F8Ab848D3CC24e7b391F19DaaF6a2d;
    address internal constant ROUTER = 0xfC354324B152E2A358A17182d2AF0d3f882c27D2;

    // Phase 2, broadcast 2026-10-26 at blocks 74275019-74275022, roles read back onchain.
    address internal constant EMA_ORACLE_PT_USDG_25FEB2027 = 0x9d1F315D6072be7D929aC9dd60ECfd3AD00443c1;

    // aave-risk-agents `DeployXLayer`, 2026-10-15, blocks 73,330,738 and 73,330,741, verified on
    // OKLink and read back onchain (hub, range module and pool). The AIP registers them and assigns
    // the ids below; the hub's `getAgentCount()` reads 0, so 0 and 1 are expected.
    address internal constant DISCOUNT_RATE_AGENT = 0xb00251C67dB290D0AD779903bfFeB092DAE76fFa;
    address internal constant EMODE_AGENT = 0x19ae7c91dfd35a4515595cEd305d2102C3b1B02D;
    // PROVISIONAL, predicted from `getAgentCount()` on the hub, which reads 0: the first two
    // registrations take 0 and 1, and aave-proposals-v3#1226 registers the discount agent first.
    // Agent id 0 is a legitimate hub id, so a wrong guess cannot be detected from the value —
    // assert the id-to-address pairing onchain after the AIP, and re-hash both workflows on a
    // mismatch.
    uint256 internal constant DISCOUNT_AGENT_ID = 0;
    uint256 internal constant EMODE_AGENT_ID = 1;

    // `cre workflow hash --target=xlayer-production` output, owner the Aave CRE org safe. Editing a
    // config after this point mints a new id, and the discount and risk-params ids depend on the
    // hub agent ids the AIP assigns, so they are re-hashed if the AIP lands different ones.
    bytes32 internal constant EMA_WORKFLOW_ID = 0x001c059c96fc6583e8d214d4e3aba98f05233bceb37f57a2441d825f739d002d;
    bytes32 internal constant DISCOUNT_WORKFLOW_ID = 0x003c64808fecbda4fd46777331da908c5e750fee76c44dfeeb4777f92bc9b7ca;
    bytes32 internal constant RISK_PARAMS_WORKFLOW_ID =
        0x006100968f1b8471cd689774d7ff884d990a4e7a9f97513c40c52da03a7440eb;
}
