// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ILlamaGuardOracle } from "./ILlamaGuardOracle.sol";
import { IReceiverTemplate } from "./IReceiverTemplate.sol";

contract LlamaGuardOracleProxy is IReceiverTemplate {
    ILlamaGuardOracle public s_llamaGuardOracle;

    struct Update {
        uint256 supply;
        uint256 price;
        uint256 state;
    }

    constructor(
        address llamaGuardOracleAddress,
        address expectedAuthor,
        bytes10 expectedWorkflowName
    )
        IReceiverTemplate(expectedAuthor, expectedWorkflowName)
    {
        s_llamaGuardOracle = ILlamaGuardOracle(llamaGuardOracleAddress);
    }

    /// @inheritdoc IReceiverTemplate
    function _processReport(bytes calldata report) internal override {
        Update memory u = abi.decode(report, (Update));
        s_llamaGuardOracle.updateData(u.supply, u.price, u.state);
    }
}
