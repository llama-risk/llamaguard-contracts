// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ILlamaGuardOracle } from "./interfaces/ILlamaGuardOracle.sol";
import { AbstractCreReceiver } from "./abstracts/AbstractCreReceiver.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract LlamaGuardOracleProxy is Ownable, AbstractCreReceiver {
    ILlamaGuardOracle public llamaguardOracle;
    string public description;

    error InvalidLlamaGuardOracle();

    constructor(
        address llamaGuardOracleAddress,
        address expectedAuthor,
        address expectedForwarder,
        bytes10 expectedWorkflowName,
        bytes32 expectedWorkflowId,
        string memory _description
    )
        Ownable(msg.sender)
        AbstractCreReceiver(expectedAuthor, expectedForwarder, expectedWorkflowName, expectedWorkflowId)
    {
        if (llamaGuardOracleAddress == address(0)) revert InvalidLlamaGuardOracle();

        llamaguardOracle = ILlamaGuardOracle(llamaGuardOracleAddress);
        description = _description;
    }

    /// @inheritdoc AbstractCreReceiver
    function _processReport(bytes calldata report) internal override {
        llamaguardOracle.updateData(report);
    }

    function setLlamaGuardOracle(address newLlamaGuardOracle) external onlyOwner {
        ILlamaGuardOracle newLlamaguardOracle = ILlamaGuardOracle(newLlamaGuardOracle);
        if (newLlamaguardOracle.hasWriteAccess(address(this)) == false) revert InvalidLlamaGuardOracle();
        llamaguardOracle = newLlamaguardOracle;
    }

    function setIsReportWriteSecured(bool enabled) external onlyOwner {
        isReportWriteSecured = enabled;
    }
}
