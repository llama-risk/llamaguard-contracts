// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { AaveV3Ethereum } from "aave-address-book/AaveV3Ethereum.sol";
import { MiscEthereum } from "aave-address-book/MiscEthereum.sol";

/// @title EthereumCoreExternalAddresses
/// @notice Every address the PT oracle stack on Aave V3 Ethereum Core depends on but does NOT
///         deploy. Aave- and Chainlink-owned contracts live here; the ACL assignments that are
///         LlamaRisk's to make live in `EthereumCoreConfig`.
/// @dev    Everything here is chain scoped, so a second PT asset on Ethereum Core reuses this file
///         unchanged.
///
///         Scoped to phase 1. The agent infrastructure (`AGENT_HUB`, `RANGE_VALIDATION_MODULE`,
///         `CONFIG_ENGINE`), the per-asset Aave reads (`POOL`, `ORACLE`) and the CRE addresses
///         (`FORWARDER`, workflow owner) arrive with the phases that use them, so that every
///         constant in this file is one a script in this PR actually reads.
///
///         Values come from `aave-address-book` wherever the pinned book carries them, so a book
///         bump surfaces as a diff here rather than as a stale literal.
library EthereumCoreExternalAddresses {
    // ============================================================================================
    // Chain
    // ============================================================================================

    uint256 internal constant ETHEREUM_CHAIN_ID = 1;

    // ============================================================================================
    // Aave V3 Ethereum Core (governance owned)
    // ============================================================================================

    /// @notice Short executor of the Aave governance payloads controller. Owns the AgentHub, holds
    ///         `DEFAULT_ADMIN_ROLE` on the ACL manager, and is the owner this deployment hands the
    ///         `PTParameterRegistry` to at construction.
    /// @dev    Equal to `GovernanceV3Ethereum.EXECUTOR_LVL_1`, which is the name the AIP payload
    ///         uses for the same address.
    address internal constant AAVE_EXECUTOR = AaveV3Ethereum.ACL_ADMIN;

    /// @notice The Aave protocol emergency multisig, and the Router's `guardian`.
    /// @dev    Verified onchain: `ACL_MANAGER.isEmergencyAdmin(this)` is true and it is a Safe with
    ///         a threshold of 4.
    ///
    ///         The guardian can `pause` and nothing else; `unpause` is owner-only, so governance can
    ///         stop this stack without a proposal and only the LlamaRisk safe can restart it.
    ///         Neither side can trap the other, and the worst a compromised guardian achieves is an
    ///         outage, which is the recoverable direction.
    ///
    ///         This is the only fast lever Aave has over the stack. Every other governance response
    ///         (`isAgentEnabled`, the hub registration, the ACL grants) is owned by the Executor and
    ///         therefore costs an AIP. Because it is their multisig and not ours, it belongs in the
    ///         ARFC text: a lever nobody knows they hold is not a lever.
    address internal constant AAVE_PROTOCOL_GUARDIAN = MiscEthereum.PROTOCOL_GUARDIAN;

    /// @dev Holds `RISK_ADMIN` for both agents once the AIP grants it. No script here can call it,
    ///      because its `DEFAULT_ADMIN_ROLE` is the Executor's. Phase 3 reads it to confirm the
    ///      payload actually made the grant before any route goes live.
    address internal constant AAVE_ACL_MANAGER = address(AaveV3Ethereum.ACL_MANAGER);

    // ============================================================================================
    // Chaos Labs agent infrastructure (governance owned)
    // ============================================================================================

    /// @dev The shared production hub. Both agents are deployed and registered by the AIP, so
    ///      nothing in `script/` writes here; phase 3 only reads it to confirm what the payload did.
    address internal constant AGENT_HUB = MiscEthereum.AGENT_HUB;

    /// @dev Bounds every parameter step an agent injects. A freshly assigned agent id inherits no
    ///      default config and the module reads a missing one as a zero bound, so an unset range is
    ///      not a loose stack, it is a dead one. Phase 3 reads it for exactly that reason.
    address internal constant RANGE_VALIDATION_MODULE = MiscEthereum.RANGE_VALIDATION_MODULE;

    // ============================================================================================
    // Chainlink CRE
    // ============================================================================================

    /// @notice KeystoneForwarder on Ethereum mainnet. Every route pins it, and the Router accepts
    ///         `onReport` from no other address.
    address internal constant CRE_FORWARDER = 0x0b93082D9b3C7C97fAcd250082899BAcf3af3885;

    /// @notice The CRE organisation multisig that owns and deploys the three workflows. Pinned as
    ///         `expectedAuthor` on every route, so a report signed for a workflow owned by anyone
    ///         else is rejected onchain. Because it is a multisig, every `cre workflow deploy` runs
    ///         `--unsigned` and is executed from the safe.
    address internal constant CRE_WORKFLOW_OWNER = 0x73494691C9B28b91A0b4C9dF213c1893fddA3a3B;
}
