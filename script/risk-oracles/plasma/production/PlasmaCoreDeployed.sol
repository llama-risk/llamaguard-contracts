// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { PlasmaCoreConfig } from "./PlasmaCoreConfig.sol";

/// @title PlasmaCoreDeployed
/// @notice What the Plasma production activation produced. Each phase reads its inputs from here,
///         so every block has to be filled in and saved before the next phase runs.
/// @dev    Each phase prints its block ready to paste. Nothing is read from env, so a stale shell
///         cannot feed one script a different address than another, and the committed file is the
///         record of what the run used.
///
///         Unset means zero, and the scripts revert on it, naming the constant. The two agent ids
///         are the exception, because 0 is a legitimate AgentHub id, so they use an explicit
///         sentinel and phase 3 checks each id against the hub instead.
///
///         The two agents are deployed and registered by the AIP, so their addresses and ids are
///         read off the hub after the payload executes rather than pasted from a broadcast of ours.
library PlasmaCoreDeployed {
    // ============================================================================================
    // Phase 1, `1_ActivatePlasmaCore.s.sol` — chain scoped, deployed once
    // ============================================================================================

    /// @notice The BGD stock RiskOracle. This is also the AIP payload's `LLAMARISK_RISK_ORACLE`,
    ///         which is why phase 1 is the gate on the payload being fillable.
    address internal constant RISK_ORACLE = address(0);

    /// @dev Owned by the Aave Executor from construction, updater is the LlamaRisk safe.
    address internal constant PT_PARAMETER_REGISTRY = address(0);

    /// @dev Updater is the LlamaRisk safe, guardian is the Aave protocol guardian. Ownership is
    ///      `Ownable2Step` and the safe is `pendingOwner` until it calls `acceptOwnership`.
    address internal constant ROUTER = address(0);

    // ============================================================================================
    // Phase 2, `2_ActivatePTsUSDe22OCT2026.s.sol` — one per PT asset
    // ============================================================================================

    /// @dev `DEFAULT_ADMIN_ROLE` is the LlamaRisk safe, `WRITER_ROLE` is the Router and nothing
    ///      else. `maxPriceDeviation` ships at zero, which is the deviation guard off.
    address internal constant EMA_ORACLE_PT_SUSDE_22OCT2026 = address(0);

    // ============================================================================================
    // The AIP — deployed and registered by the payload, read back off the hub
    // ============================================================================================

    /// @notice The agent contracts the payload deployed. Recorded here so phase 3 can assert that
    ///         the id it is about to wire resolves to the contract governance actually registered.
    address internal constant DISCOUNT_RATE_AGENT = address(0);
    address internal constant EMODE_AGENT = address(0);

    /// @notice The ids the AgentHub assigned. Handed out sequentially by `agentCount++`, so they
    ///         cannot be known before the payload executes. NOT the shadow hub's ids 0 and 1.
    uint256 internal constant DISCOUNT_AGENT_ID = PlasmaCoreConfig.AGENT_ID_UNSET;
    uint256 internal constant EMODE_AGENT_ID = PlasmaCoreConfig.AGENT_ID_UNSET;

    // ============================================================================================
    // `cre workflow deploy`
    // ============================================================================================

    /// @notice Reported by each `cre workflow deploy`. A workflow id hashes the wasm together with
    ///         the config, so editing a config after this point mints a new id and leaves the route
    ///         registered against the old one. The names themselves live with the asset, in
    ///         `assets/PTsUSDe22OCT2026.sol`.
    bytes32 internal constant EMA_WORKFLOW_ID = bytes32(0);
    bytes32 internal constant DISCOUNT_WORKFLOW_ID = bytes32(0);
    bytes32 internal constant RISK_PARAMS_WORKFLOW_ID = bytes32(0);
}
