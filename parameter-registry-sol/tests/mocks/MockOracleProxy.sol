// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.26 <0.9.0;

contract MockOracleProxy {
    address public aggregator;

    constructor(address _aggregator) {
        aggregator = _aggregator;
    }

    function setAggregator(address _aggregator) external {
        aggregator = _aggregator;
    }
}