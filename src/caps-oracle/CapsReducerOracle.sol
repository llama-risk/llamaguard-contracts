// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { IRiskOracle } from "chaos-agents/contracts/dependencies/IRiskOracle.sol";
import { ICapsReducerOracle } from "./interfaces/ICapsReducerOracle.sol";
import { ICapsRangeValidationModule } from "./interfaces/ICapsRangeValidationModule.sol";

/// @title CapsReducerOracle
/// @notice Stateless view contract registered on AgentHub as the `riskOracle` of the cut agentIds of one kind
///         of one RVM. It returns the cut that the RVM accepts in the current block, or reverts so that
///         AgentHub skips the asset.
/// @dev No admin, no storage. The RVM and the kind are immutable, so one CapsReducerOracle per (Pool, kind).
///      It implements only `getLatestUpdateByParameterAndMarket`, the `IRiskOracle` read AgentHub calls. The
///      cut rule lives only in the RVM.
contract CapsReducerOracle is ICapsReducerOracle {
    /// @notice Zero address passed as the RVM.
    error ZeroAddress();

    /// @inheritdoc ICapsReducerOracle
    ICapsRangeValidationModule public immutable RVM;

    /// @inheritdoc ICapsReducerOracle
    ICapsRangeValidationModule.CapKind public immutable KIND;

    /// @param rvm the rate-limiter RVM this oracle reads
    /// @param kind the cap kind this oracle serves
    constructor(ICapsRangeValidationModule rvm, ICapsRangeValidationModule.CapKind kind) {
        if (address(rvm) == address(0)) revert ZeroAddress();
        RVM = rvm;
        KIND = kind;
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
        (bool due, uint256 currentCap, uint256 newCap) = RVM.previewCut(asset, KIND);
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
