// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { AaveV3Monad } from "aave-address-book/AaveV3Monad.sol";
import { MiscMonad } from "aave-address-book/MiscMonad.sol";

/// @title MonadCoreExternalAddresses
/// @notice Every address the stack depends on but does NOT deploy. Book values wherever the
///         pinned `aave-address-book` carries them.
/// @dev    Two groups are literals here because the book carries no entry for them on this chain:
///         the agent-hub pair, which is deployed but not yet published, and the CRE forwarder, which
///         is per chain and has never been a book value. Both are asserted onchain rather than
///         trusted — see `MonadCoreConfig.validateAgentDependencies`.
library MonadCoreExternalAddresses {
    uint256 internal constant MONAD_CHAIN_ID = 143;

    /// @notice Equal to `GovernanceV3Monad.EXECUTOR_LVL_1`, the name the AIP uses.
    address internal constant AAVE_EXECUTOR = AaveV3Monad.ACL_ADMIN;

    /// @notice Router `guardian`: can `pause`, cannot `unpause`.
    address internal constant AAVE_PROTOCOL_GUARDIAN = MiscMonad.PROTOCOL_GUARDIAN;

    /// @dev Phase 3 reads it to confirm the AIP's RISK_ADMIN grants.
    address internal constant AAVE_ACL_MANAGER = address(AaveV3Monad.ACL_MANAGER);

    /// @dev Deployed; proxy and ProxyAdmin are both owned by `AAVE_EXECUTOR`. Replace with
    ///      `MiscMonad.AGENT_HUB` once the book carries it.
    address internal constant AGENT_HUB = 0xa1Cf1e3D3fC743c0fd0e38f631A843372b7169DB;

    /// @dev Deployed. A missing range config reads as a zero bound, so a wrong address here fails
    ///      open rather than loudly. Replace with `MiscMonad.RANGE_VALIDATION_MODULE` once published.
    address internal constant RANGE_VALIDATION_MODULE = 0x863D5B3f24E6b84564432dd20606a82bB1C61dC5;

    /// @notice KeystoneForwarder on Monad; every route pins it.
    /// @dev    Per chain, from the Chainlink CRE forwarder directory:
    ///         https://docs.chain.link/cre/guides/workflow/using-evm-client/forwarder-directory-ts
    ///         `typeAndVersion()` reads "KeystoneForwarder 1.0.0" on Monad. Addresses differ per
    ///         deployment with no derivable pattern, so look each chain up rather than reusing
    ///         another's; the fork test asserts this one.
    address internal constant CRE_FORWARDER = 0x76c9cf548b4179F8901cda1f8623568b58215E62;

    /// @notice The Aave CRE org safe, same as Ethereum and Plasma production: the WorkflowRegistry
    ///         lives on ethereum-mainnet for every target chain.
    /// @dev    Must equal the CRE deploy target's `workflow-owner-address`.
    address internal constant CRE_WORKFLOW_OWNER = 0x73494691C9B28b91A0b4C9dF213c1893fddA3a3B;
}
