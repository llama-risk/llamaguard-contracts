// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { AaveV3XLayer } from "aave-address-book/AaveV3XLayer.sol";
import { GovernanceV3XLayer } from "aave-address-book/GovernanceV3XLayer.sol";
import { MiscXLayer } from "aave-address-book/MiscXLayer.sol";

/// @title XLayerCoreExternalAddresses
/// @notice Every address the stack depends on but does NOT deploy. Book values wherever the
///         pinned `aave-address-book` carries them.
/// @dev    Two groups are literals here because the book carries no entry for them on this chain:
///         the agent-hub pair, which is not deployed yet, and the CRE forwarder, which is per chain
///         and has never been a book value. Both are asserted onchain rather than trusted — see
///         `XLayerCoreConfig.validateAgentDependencies` and the fork test.
library XLayerCoreExternalAddresses {
    uint256 internal constant XLAYER_CHAIN_ID = 196;

    /// @notice Equal to `AaveV3XLayer.ACL_ADMIN`; the fork test asserts the two agree.
    address internal constant AAVE_EXECUTOR = GovernanceV3XLayer.EXECUTOR_LVL_1;

    /// @notice Router `guardian`: can `pause`, cannot `unpause`.
    address internal constant AAVE_PROTOCOL_GUARDIAN = MiscXLayer.PROTOCOL_GUARDIAN;

    /// @dev Phase 3 reads it to confirm the AIP's RISK_ADMIN grants.
    address internal constant AAVE_ACL_MANAGER = address(AaveV3XLayer.ACL_MANAGER);

    /// @dev From the aave-agent-hub `DeployXLayer` broadcast; proxy and ProxyAdmin both owned by
    ///      `AAVE_EXECUTOR`. Deployed 2026-10-15, blocks 73,330,114-118, read back onchain.
    ///      Replace with `MiscXLayer.AGENT_HUB` once the book carries it.
    address internal constant AGENT_HUB = 0x7532F38Be8AB746DD6c1B686A9aAED3400eD35a0;

    /// @dev From the same broadcast. A missing range config reads as a zero bound, so a wrong
    ///      address here fails open rather than loudly. Replace with
    ///      `MiscXLayer.RANGE_VALIDATION_MODULE` once published.
    address internal constant RANGE_VALIDATION_MODULE = 0x863D5B3f24E6b84564432dd20606a82bB1C61dC5;

    /// @notice KeystoneForwarder on X Layer (`ethereum-mainnet-xlayer-1`); every route pins it.
    /// @dev    Per chain, from the Chainlink CRE forwarder directory:
    ///         https://docs.chain.link/cre/guides/workflow/using-evm-client/forwarder-directory-ts
    ///         `typeAndVersion()` reads "KeystoneForwarder 1.0.0" on X Layer. Look each chain up
    ///         rather than reusing another's, even where the address happens to match; the fork test
    ///         asserts this one.
    address internal constant CRE_FORWARDER = 0x76c9cf548b4179F8901cda1f8623568b58215E62;

    /// @notice The Aave CRE org safe, same as every other production chain: the WorkflowRegistry
    ///         lives on ethereum-mainnet for every target chain.
    /// @dev    Must equal the CRE deploy target's `workflow-owner-address`.
    address internal constant CRE_WORKFLOW_OWNER = 0x73494691C9B28b91A0b4C9dF213c1893fddA3a3B;
}
