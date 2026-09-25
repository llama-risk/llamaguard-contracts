// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { AaveV3Plasma } from "aave-address-book/AaveV3Plasma.sol";
import { MiscPlasma } from "aave-address-book/MiscPlasma.sol";

/// @title PlasmaCoreExternalAddresses
/// @notice Every address the stack depends on but does NOT deploy. Book values wherever the
///         pinned `aave-address-book` carries them.
library PlasmaCoreExternalAddresses {
    uint256 internal constant PLASMA_CHAIN_ID = 9745;

    /// @notice Equal to `GovernanceV3Plasma.EXECUTOR_LVL_1`, the name the AIP uses.
    address internal constant AAVE_EXECUTOR = AaveV3Plasma.ACL_ADMIN;

    /// @notice Router `guardian`: can `pause`, cannot `unpause`.
    address internal constant AAVE_PROTOCOL_GUARDIAN = MiscPlasma.PROTOCOL_GUARDIAN;

    /// @dev Phase 3 reads it to confirm the AIP's RISK_ADMIN grants.
    address internal constant AAVE_ACL_MANAGER = address(AaveV3Plasma.ACL_MANAGER);

    /// @dev Aave's production hub, NOT the EOA-owned shadow hub `0x7d1C…E949`. Read-only here:
    ///      the agents are the AIP's to register.
    address internal constant AGENT_HUB = MiscPlasma.AGENT_HUB;

    /// @dev A fresh agent id has no range config and a missing one reads as a zero bound.
    address internal constant RANGE_VALIDATION_MODULE = MiscPlasma.RANGE_VALIDATION_MODULE;

    /// @notice KeystoneForwarder on Plasma; every route pins it. No book entry; verified live.
    address internal constant CRE_FORWARDER = 0x7BCcaFBD064cB3658476066Cc33ceE3F3414c04c;

    /// @notice The Aave CRE org safe, same as Ethereum production: the WorkflowRegistry lives on
    ///         ethereum-mainnet for every target chain.
    /// @dev    Must equal the CRE deploy target's `workflow-owner-address`.
    address internal constant CRE_WORKFLOW_OWNER = 0x73494691C9B28b91A0b4C9dF213c1893fddA3a3B;
}
