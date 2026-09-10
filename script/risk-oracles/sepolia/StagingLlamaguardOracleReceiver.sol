// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { IReceiver } from "@chainlink/contracts/src/v0.8/keystone/interfaces/IReceiver.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title StagingLlamaguardOracleReceiver
/// @notice Minimal forwarder-only CRE receiver used for `cre workflow simulate --broadcast`
///         when the upstream sink is `LlamaGuardOracle` instead of the BGD `RiskOracle`.
/// @dev The report is expected to be `abi.encode(ILlamaGuardOracle.UpdateInput)` and is
///      forwarded directly into `updateLatestRiskRoundData(...)` on the configured oracle.
contract StagingLlamaguardOracleReceiver is IReceiver {
    bytes4 public constant UPDATE_SELECTOR =
        bytes4(keccak256("updateLatestRiskRoundData((string,bytes,string,bytes,uint256))"));

    address public immutable FORWARDER;
    address public immutable LLAMAGUARD_ORACLE;
    string public description;

    event ReportForwarded(address indexed llamaGuardOracle, bytes4 updateSelector);

    error InvalidForwarder(address received, address expected);
    error PublishFailed(bytes returnData);
    error ZeroAddress();

    constructor(address forwarder_, address llamaGuardOracle_, string memory description_) {
        if (forwarder_ == address(0) || llamaGuardOracle_ == address(0)) revert ZeroAddress();

        FORWARDER = forwarder_;
        LLAMAGUARD_ORACLE = llamaGuardOracle_;
        description = description_;
    }

    function onReport(bytes calldata, bytes calldata report) external override {
        if (msg.sender != FORWARDER) {
            revert InvalidForwarder(msg.sender, FORWARDER);
        }

        (bool ok, bytes memory ret) = LLAMAGUARD_ORACLE.call(abi.encodePacked(UPDATE_SELECTOR, report));
        if (!ok) revert PublishFailed(ret);

        emit ReportForwarded(LLAMAGUARD_ORACLE, UPDATE_SELECTOR);
    }

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IReceiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
