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
        bytes10 expectedWorkflowName,
        string memory _description
    )
        Ownable(msg.sender)
        AbstractCreReceiver(expectedAuthor, expectedWorkflowName)
    {
        if (llamaGuardOracleAddress == address(0)) revert InvalidLlamaGuardOracle();

        llamaguardOracle = ILlamaGuardOracle(llamaGuardOracleAddress);
        description = _description;
    }

    /// @inheritdoc AbstractCreReceiver
    function _processReport(bytes calldata report) internal override {
        llamaguardOracle.updateData(report);
    }

    function changeLlamaGuardOracle(address newLlamaGuardOracle) external onlyOwner {
        ILlamaGuardOracle newLlamaguardOracle = ILlamaGuardOracle(newLlamaGuardOracle);
        if (newLlamaguardOracle.hasWriteAccess(address(this)) == false) revert InvalidLlamaGuardOracle();
        llamaguardOracle = newLlamaguardOracle;
    }
}
