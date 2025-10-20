// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AggregatorV3} from "./AggregatorV3.sol";
import {ILlamaGuardOracle} from "./interfaces/ILlamaGuardOracle.sol";

contract LlamaGuardOracle is AggregatorV3, ILlamaGuardOracle {
    struct UpdateData {
        uint256 supply;
        uint256 price;
        uint256 state;
    }

    uint256 public supply;
    uint256 public state;

    constructor(uint8 decimals, string memory description, uint256 version)
        AggregatorV3(decimals, description, version)
    {}

    /// @notice Update the data from the oracle
    /// @param data The update data containing supply, price, and state
    function updateData(bytes calldata data) external checkAccess() {
        UpdateData memory decodedData = abi.decode(data, (UpdateData));
        updateLatestRoundData(int256(decodedData.price));

        emit UpdateReceived(supply = decodedData.supply, decodedData.price, state = decodedData.state);
    }

    /// @notice Get the data from the oracle
    /// @return supply The supply of the asset in the latest round
    /// @return state The state of the workflow
    /// @return price The price of the asset in the latest round
    /// @return startedAt The timestamp when the latest round started
    function getData() public view returns (uint256, uint256, int256, uint256) {
        (, int256 answer, uint256 startedAt,,) = this.latestRoundData();
        return (supply, state, answer, startedAt);
    }
}
