// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { IRiskOracle } from "chaos-agents/contracts/dependencies/IRiskOracle.sol";
import { ICapsRangeValidationModule } from "./ICapsRangeValidationModule.sol";

/**
 * @title ICapsReducerOracle
 * @notice Stateless view contract that AgentHub calls as the `riskOracle` of the borrow and supply cut
 *         agentIds of one RVM. It returns the cut that the RVM accepts now, or reverts so that AgentHub skips
 *         the asset.
 * @dev One instance per Pool. The kind comes from the update type, matched to the RVM's update types. It
 *      computes nothing itself: the rule lives in the RVM.
 */
interface ICapsReducerOracle {
    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice The RVM reports no cut due for this asset in this block.
    error NoCutDue(address asset);

    /// @notice The update type matches neither the RVM's borrow nor its supply update type.
    error UnknownUpdateType(string updateType);

    // ═══════════════════════════════════════════════════════════════════════════
    // IMMUTABLES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice The RVM this oracle reads. The RVM serves one Pool.
    function RVM() external view returns (ICapsRangeValidationModule);

    /// @notice keccak256 of the RVM's borrow cap update type, read at construction.
    function BORROW_UPDATE_TYPE_HASH() external view returns (bytes32);

    /// @notice keccak256 of the RVM's supply cap update type, read at construction.
    function SUPPLY_UPDATE_TYPE_HASH() external view returns (bytes32);

    // ═══════════════════════════════════════════════════════════════════════════
    // ADAPTER READ
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice The cut for `asset`, in the shape AgentHub expects from a RiskOracle.
     * @dev View. Reverts UnknownUpdateType, NoCutDue. `newValue` is abi.encode(newCap) and `previousValue` is
     *      abi.encode(currentCap), both whole tokens.
     * @param updateType the cut agentId's update type; selects the cap kind and is echoed in the update
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
