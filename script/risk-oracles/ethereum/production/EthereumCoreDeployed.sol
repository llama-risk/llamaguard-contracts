// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { EthereumCoreConfig } from "./EthereumCoreConfig.sol";

/// @title EthereumCoreDeployed
/// @notice What the Ethereum Core production activation produced. Each phase reads its inputs from
///         here, so every block has to be filled in and saved before the next phase runs.
/// @dev    Each phase prints its block ready to paste. Nothing is read from env, so a stale shell
///         cannot feed one script a different address than another, and the committed file is the
///         record of what the run used.
///
///         Unset means zero, and the scripts revert on it, naming the constant. The two agent ids
///         are the exception, because 0 is a legitimate AgentHub id, so they use an explicit
///         sentinel and phase 3 checks each id against the hub instead.
///
///         Note which blocks this deployment does NOT produce. The two agents are deployed and
///         registered by the AIP, so their addresses and ids are both read off the hub after the
///         payload executes rather than pasted from a broadcast of ours.
library EthereumCoreDeployed {
    // ============================================================================================
    // Phase 1, `1_ActivateEthereumCore.s.sol` — chain scoped, deployed once
    // ============================================================================================

    /// @notice The BGD stock RiskOracle. This is also the AIP payload's `LLAMARISK_RISK_ORACLE`,
    ///         which is why phase 1 is the gate on the payload being fillable rather than on
    ///         anything the payload calls.
    /// @dev    Owned by the LlamaRisk safe. The Router is its only authorised sender.
    address internal constant RISK_ORACLE = 0x683d1A91599F971252Ef171eF1F987172be8369A;

    /// @dev Owned by the Aave Executor from construction, updater is the LlamaRisk safe.
    address internal constant PT_PARAMETER_REGISTRY = 0x37370932045d20C01A62b3e7c21134A1C6365D38;

    /// @dev Updater is the LlamaRisk safe, guardian is the Aave protocol guardian. Ownership is
    ///      `Ownable2Step` and the safe is `pendingOwner` until it calls `acceptOwnership`.
    address internal constant ROUTER = 0x1D85000D54ea1185C43E4f2b32833524d3cF3507;

    // ============================================================================================
    // Phase 2, `2_ActivatePTsrUSDe22OCT2026.s.sol` — one per PT asset
    // ============================================================================================

    /// @dev `DEFAULT_ADMIN_ROLE` is the LlamaRisk safe, `WRITER_ROLE` is the Router and nothing
    ///      else. `maxPriceDeviation` is zero, which is the deviation guard off.
    address internal constant EMA_ORACLE_PT_SRUSDE_22OCT2026 = 0xc63D0747457dA82E4dc1C6a06Fb587622137d887;

    // ============================================================================================
    // The AIP — deployed and registered by the payload, read back off the hub
    // ============================================================================================

    /// @notice The agent contracts the payload deployed. Recorded here so phase 3 can assert that
    ///         the id it is about to wire resolves to the contract governance actually registered,
    ///         rather than trusting a number pasted from a block explorer.
    address internal constant DISCOUNT_RATE_AGENT = address(0);
    address internal constant EMODE_AGENT = address(0);

    /// @notice The ids the AgentHub assigned. Handed out sequentially by `agentCount++`, so they
    ///         cannot be known before the payload executes.
    /// @dev    Phase 3 requires `getAgentAddress(DISCOUNT_AGENT_ID)` to equal `DISCOUNT_RATE_AGENT`
    ///         above, which is what catches the two ids being transcribed the wrong way round.
    uint256 internal constant DISCOUNT_AGENT_ID = EthereumCoreConfig.AGENT_ID_UNSET;
    uint256 internal constant EMODE_AGENT_ID = EthereumCoreConfig.AGENT_ID_UNSET;

    // ============================================================================================
    // `cre workflow deploy`
    // ============================================================================================

    /// @notice Reported by each `cre workflow deploy`. A workflow id hashes the wasm together with
    ///         the config, so editing a config after this point mints a new id and leaves the route
    ///         registered against the old one. The names themselves live with the asset, in
    ///         `assets/PTsrUSDe22OCT2026.sol`.
    bytes32 internal constant EMA_WORKFLOW_ID = 0x0091413fc6ddedb789e424421fd18cd18b4a64fe139eaa9e10759a68a5cae583;
    bytes32 internal constant DISCOUNT_WORKFLOW_ID = 0x0030df3e67d349d2100820d1de934c111f7b005718993b3e4d43d087753cc6fe;
    bytes32 internal constant RISK_PARAMS_WORKFLOW_ID =
        0x00c672ab84adbd3c64d17c7dd3fe67860b7a4da4f7d0d952d46989ce109b1933;
}
