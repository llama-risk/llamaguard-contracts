// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { AaveV3Plasma } from "aave-address-book/AaveV3Plasma.sol";
import { MiscPlasma } from "aave-address-book/MiscPlasma.sol";

/// @title PlasmaCoreExternalAddresses
/// @notice Every address the PT oracle stack on Aave V3 Plasma depends on but does NOT deploy.
///         Aave- and Chainlink-owned contracts live here; the ACL assignments that are LlamaRisk's
///         to make live in `PlasmaCoreConfig`.
/// @dev    Mirror of `EthereumCoreExternalAddresses`, same scoping rules: chain scoped, so a second
///         PT asset on Plasma reuses this file unchanged, and every constant here is one a script
///         in this directory actually reads.
///
///         Values come from `aave-address-book` wherever the pinned book carries them, so a book
///         bump surfaces as a diff here rather than as a stale literal. The pinned book carries the
///         whole Plasma governance surface, the AgentHub and the RangeValidationModule.
library PlasmaCoreExternalAddresses {
    // ============================================================================================
    // Chain
    // ============================================================================================

    uint256 internal constant PLASMA_CHAIN_ID = 9745;

    // ============================================================================================
    // Aave V3 Plasma (governance owned)
    // ============================================================================================

    /// @notice Short executor of the Aave governance payloads controller on Plasma. Owns the
    ///         AgentHub, holds `DEFAULT_ADMIN_ROLE` on the ACL manager, and is the owner this
    ///         deployment hands the `PTParameterRegistry` to at construction.
    /// @dev    Equal to `GovernanceV3Plasma.EXECUTOR_LVL_1`, which is the name the AIP payload uses
    ///         for the same address.
    address internal constant AAVE_EXECUTOR = AaveV3Plasma.ACL_ADMIN;

    /// @notice The Aave protocol guardian on Plasma, and the Router's `guardian`.
    /// @dev    The guardian can `pause` and nothing else; `unpause` is owner-only, so governance can
    ///         stop this stack without a proposal and only the LlamaRisk safe can restart it.
    address internal constant AAVE_PROTOCOL_GUARDIAN = MiscPlasma.PROTOCOL_GUARDIAN;

    /// @dev Holds `RISK_ADMIN` for both agents once the AIP grants it. No script here can call it,
    ///      because its `DEFAULT_ADMIN_ROLE` is the Executor's. Phase 3 reads it to confirm the
    ///      payload actually made the grant before any route goes live.
    address internal constant AAVE_ACL_MANAGER = address(AaveV3Plasma.ACL_MANAGER);

    // ============================================================================================
    // Chaos Labs agent infrastructure (governance owned)
    // ============================================================================================

    /// @dev The shared production hub on Plasma. NOT the EOA-owned shadow hub
    ///      `0x7d1C3F872022b13B931C4E50C60818fAaC7dE949`: both agents are deployed and registered
    ///      by the AIP, so nothing in `script/` writes here; phase 3 only reads it to confirm what
    ///      the payload did.
    address internal constant AGENT_HUB = MiscPlasma.AGENT_HUB;

    /// @dev Bounds every parameter step an agent injects. A freshly assigned agent id inherits no
    ///      default config and the module reads a missing one as a zero bound, so an unset range is
    ///      not a loose stack, it is a dead one. Phase 3 reads it for exactly that reason.
    address internal constant RANGE_VALIDATION_MODULE = MiscPlasma.RANGE_VALIDATION_MODULE;

    // ============================================================================================
    // Chainlink CRE
    // ============================================================================================

    /// @notice KeystoneForwarder on Plasma. Every route pins it, and the Router accepts `onReport`
    ///         from no other address.
    /// @dev    No book entry. Verified live: it is the forwarder the shadow routes pin and the
    ///         sender of every shadow report accepted on chain 9745.
    address internal constant CRE_FORWARDER = 0x7BCcaFBD064cB3658476066Cc33ceE3F3414c04c;

    /// @notice The LlamaRisk multisig that owns and deploys the three workflows, pinned as
    ///         `expectedAuthor` on every route. Lives on ethereum-mainnet, where the CRE
    ///         WorkflowRegistry is; it needs no code on Plasma.
    /// @dev    Must equal the `workflow-owner-address` of the CRE deploy target, or the hashed
    ///         workflow ids will not be the deployed ids and every report is rejected onchain.
    ///         Because it is a multisig, every `cre workflow deploy` runs `--unsigned` and is
    ///         executed from the safe.
    address internal constant CRE_WORKFLOW_OWNER = 0x4EDEaFc9b862F08464423EFe9423153B22B28f17;
}
