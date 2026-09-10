// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { IReceiver } from "@chainlink/contracts/src/v0.8/keystone/interfaces/IReceiver.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title StagingRiskOracleReceiver
/// @notice Minimal forwarder-only CRE receiver used for `cre workflow simulate --broadcast`
///         against Sepolia while the official `MockKeystoneForwarder` still omits workflow
///         metadata.
/// @dev This contract intentionally performs only the mandatory forwarder check. It then forwards
///      the raw report bytes into a single configured `RiskOracle` publish entrypoint. Production
///      multi-workflow identity validation lives in `LlamaguardRiskOracleRouter`; this receiver is
///      the non-production ingress that keeps simulation aligned with official CRE behavior.
contract StagingRiskOracleReceiver is IReceiver {
    address public immutable FORWARDER;
    address public immutable RISK_ORACLE;
    bytes4 public immutable PUBLISH_SELECTOR;
    string public description;

    event ReportForwarded(address indexed riskOracle, bytes4 publishSelector);

    error InvalidForwarder(address received, address expected);
    error PublishFailed(bytes returnData);
    error ZeroAddress();
    error ZeroSelector();

    constructor(address forwarder_, address riskOracle_, bytes4 publishSelector_, string memory description_) {
        if (forwarder_ == address(0) || riskOracle_ == address(0)) revert ZeroAddress();
        if (publishSelector_ == bytes4(0)) revert ZeroSelector();

        FORWARDER = forwarder_;
        RISK_ORACLE = riskOracle_;
        PUBLISH_SELECTOR = publishSelector_;
        description = description_;
    }

    function onReport(bytes calldata, bytes calldata report) external override {
        if (msg.sender != FORWARDER) {
            revert InvalidForwarder(msg.sender, FORWARDER);
        }

        (bool ok, bytes memory ret) = RISK_ORACLE.call(abi.encodePacked(PUBLISH_SELECTOR, report));
        if (!ok) revert PublishFailed(ret);

        emit ReportForwarded(RISK_ORACLE, PUBLISH_SELECTOR);
    }

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IReceiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
