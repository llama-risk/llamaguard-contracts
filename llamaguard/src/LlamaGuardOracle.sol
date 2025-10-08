// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { AggregatorV3 } from "./AggregatorV3.sol";
import { ILlamaGuardOracle } from "./ILlamaGuardOracle.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract LlamaGuardOracle is Ownable2Step, AggregatorV3, ILlamaGuardOracle {
    address public proxyAddress;

    uint256 public supply;
    uint256 public state;

    modifier onlyProxy() {
        require(msg.sender == proxyAddress, "Caller is not the authorized proxy");
        _;
    }

    constructor(uint8 decimals, string memory description, uint256 version)
        Ownable(msg.sender)
        AggregatorV3(decimals, description, version)
    { }

    function setProxyAddress(address _proxyAddress) external onlyOwner {
        proxyAddress = _proxyAddress;
    }

    /// @notice Update the data from the oracle
    /// @param data The update data containing supply, price, and state
    function updateData(ILlamaGuardOracle.UpdateData calldata data) external onlyProxy {
        updateLatestRoundData(int256(data.price));

        state = data.state;
        supply = data.supply;

        emit UpdateReceived(data.supply, data.price, data.state);
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
