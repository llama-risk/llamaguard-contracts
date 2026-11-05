// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { IRiskOracle } from "chaos-agents/contracts/dependencies/IRiskOracle.sol";
import { ICapsReducerOracle } from "./interfaces/ICapsReducerOracle.sol";
import { ICapsRangeValidationModule } from "./interfaces/ICapsRangeValidationModule.sol";

/// @title CapsReducerOracle
/// @notice Stateless view contract registered on AgentHub as the `riskOracle` of the borrow and supply cut
///         agentIds of one RVM. It returns the cut that the RVM accepts in the current block, or reverts so that
///         AgentHub skips the asset.
/// @dev No admin, no storage. One CapsReducerOracle per Pool. The kind comes from the `updateType` argument,
///      matched to the RVM's borrow and supply update types read once at construction. It implements only
///      `getLatestUpdateByParameterAndMarket`, the `IRiskOracle` read AgentHub calls. The cut rule lives only
///      in the RVM.
contract CapsReducerOracle is ICapsReducerOracle {
    /// @notice Zero address passed as the RVM.
    error ZeroAddress();

    /// @inheritdoc ICapsReducerOracle
    ICapsRangeValidationModule public immutable RVM;

    /// @inheritdoc ICapsReducerOracle
    bytes32 public immutable BORROW_UPDATE_TYPE_HASH;

    /// @inheritdoc ICapsReducerOracle
    bytes32 public immutable SUPPLY_UPDATE_TYPE_HASH;

    /// @param rvm the rate-limiter RVM this oracle reads
    constructor(ICapsRangeValidationModule rvm) {
        if (address(rvm) == address(0)) revert ZeroAddress();
        RVM = rvm;
        BORROW_UPDATE_TYPE_HASH = rvm.BORROW_UPDATE_TYPE_HASH();
        SUPPLY_UPDATE_TYPE_HASH = rvm.SUPPLY_UPDATE_TYPE_HASH();
    }

    /// @inheritdoc ICapsReducerOracle
    function getLatestUpdateByParameterAndMarket(
        string calldata updateType,
        address asset
    )
        external
        view
        returns (IRiskOracle.RiskParameterUpdate memory update)
    {
        bytes32 h = keccak256(bytes(updateType));
        ICapsRangeValidationModule.CapKind kind;
        if (h == BORROW_UPDATE_TYPE_HASH) {
            kind = ICapsRangeValidationModule.CapKind.BORROW;
        } else if (h == SUPPLY_UPDATE_TYPE_HASH) {
            kind = ICapsRangeValidationModule.CapKind.SUPPLY;
        } else {
            revert UnknownUpdateType(updateType);
        }

        (bool due, uint256 currentCap, uint256 newCap) = RVM.previewCut(asset, kind);
        if (!due) revert NoCutDue(asset);

        // timestamp = now passes the AgentHub expiration check. updateId = block.number lets at most one cut
        // per asset and agentId land per block.
        update.timestamp = block.timestamp;
        update.newValue = abi.encode(newCap);
        update.previousValue = abi.encode(currentCap);
        update.updateType = updateType;
        update.updateId = block.number;
        update.market = asset;
    }
}
