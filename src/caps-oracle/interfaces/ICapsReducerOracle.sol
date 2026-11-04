// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { IRiskOracle } from "chaos-agents/contracts/dependencies/IRiskOracle.sol";
import { ICapsRangeValidationModule } from "./ICapsRangeValidationModule.sol";

/**
 * @title ICapsReducerOracle
 * @notice Stateless view contract that AgentHub calls as the `riskOracle` of the cut agentIds of one kind
 *         of one RVM. It returns the cut that the RVM accepts now, or reverts so that AgentHub skips the asset.
 * @dev One instance per (Pool, kind). It computes nothing itself: the rule lives in the RVM.
 */
interface ICapsReducerOracle {
    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice The RVM reports no cut due for this asset in this block.
    error NoCutDue(address asset);

    // ═══════════════════════════════════════════════════════════════════════════
    // IMMUTABLES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice The RVM this oracle reads. The RVM serves one Pool.
    function RVM() external view returns (ICapsRangeValidationModule);

    /// @notice The cap kind this oracle serves.
    function KIND() external view returns (ICapsRangeValidationModule.CapKind);

    // ═══════════════════════════════════════════════════════════════════════════
    // ADAPTER READ
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice The cut for `asset`, in the shape AgentHub expects from a RiskOracle.
     * @dev View. Reverts NoCutDue. `newValue` is abi.encode(newCap) and `previousValue` is
     *      abi.encode(currentCap), both whole tokens.
     * @param updateType the cut agentId's update type, echoed in the update and not parsed
     * @param asset the token address
     */
    function getLatestUpdateByParameterAndMarket(
        string calldata updateType,
        address asset
    )
        external
        view
        returns (IRiskOracle.RiskParameterUpdate memory);
}
