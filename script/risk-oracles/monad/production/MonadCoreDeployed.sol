// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { MonadCoreConfig } from "./MonadCoreConfig.sol";

/// @title MonadCoreDeployed
/// @notice What each phase produced; the next phase reads its inputs from here, never from env.
///         Unset means zero and the scripts revert on it. The agent ids use a sentinel because 0
///         is a legitimate hub id.
/// @dev    Each phase prints `OUTPUT:` lines; paste them here and commit before running the next
///         phase, so every recorded address is one read back onchain.
library MonadCoreDeployed {
    // Phase 1, broadcast 2026-10-02 at block 109897859-109897894, principals read back onchain.
    // RISK_ORACLE is also the AIP payload's LLAMARISK_RISK_ORACLE.
    address internal constant RISK_ORACLE = 0x4b00A38ee9396E952d07F81B26Ed1514e480dCFC;
    address internal constant PT_PARAMETER_REGISTRY = 0xA046b090C93A7a98b18e466ff770ED01116fa695;
    address internal constant ROUTER = 0x8fDdd4Ab11Ecd6A95F6d67f13166031604624B71;

    // Phase 2, broadcast 2026-10-02 at block 109899453-109899464, roles read back onchain.
    address internal constant EMA_ORACLE_PT_AUSD_17DEC2026 = 0x1D8Ec41F99578E2774A688aeE55c06Ef0c113286;

    // Predeployed 2026-10-02 at blocks 109925254 and 109925257; ownerless, immutables read back
    // onchain. The AIP registers them and assigns the ids below. Built from
    // aave-dao/aave-risk-agents at that repo's own settings (solc 0.8.27, optimizer_runs 200,
    // shanghai), so the runtime matches Ethereum and Plasma once the per-chain immutables are
    // masked out — the hub, range module, pool and oracle are immutables, so a raw cross-chain
    // bytecode diff never matches and is not the check to run.
    address internal constant DISCOUNT_RATE_AGENT = 0x9047f3084Dd26d0d8a6b0Ef9Bb8643b01dA726D3;
    address internal constant EMODE_AGENT = 0xa89C6f877380af190AFD839c0F9cBF57474162f1;
    uint256 internal constant DISCOUNT_AGENT_ID = MonadCoreConfig.AGENT_ID_UNSET;
    uint256 internal constant EMODE_AGENT_ID = MonadCoreConfig.AGENT_ID_UNSET;

    // `cre workflow hash` output, owner the Aave CRE org safe. Editing a config after this point
    // mints a new id, and the discount and risk-params ids depend on the hub agent ids the AIP
    // assigns, so they are re-hashed if the AIP lands different ones.
    bytes32 internal constant EMA_WORKFLOW_ID = bytes32(0);
    bytes32 internal constant DISCOUNT_WORKFLOW_ID = bytes32(0);
    bytes32 internal constant RISK_PARAMS_WORKFLOW_ID = bytes32(0);
}
