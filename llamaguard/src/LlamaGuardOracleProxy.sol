// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ILlamaGuardOracle } from "./interfaces/ILlamaGuardOracle.sol";
import { IReceiverTemplate } from "./interfaces/IReceiverTemplate.sol";

contract LlamaGuardOracleProxy is IReceiverTemplate {
    ILlamaGuardOracle public s_llamaGuardOracle;

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
        ILlamaGuardOracle.UpdateData memory data = abi.decode(report, (ILlamaGuardOracle.UpdateData));
        s_llamaGuardOracle.updateData(data);
    }
}
