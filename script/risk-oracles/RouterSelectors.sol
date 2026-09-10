// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IRiskOracle } from "aave-v3-risk-stewards/contracts/dependencies/IRiskOracle.sol";
import { ILlamaGuardOracle } from "llamaguard-contracts/src/interfaces/ILlamaGuardOracle.sol";

/// @title RouterSelectors
/// @notice Canonical publish selectors for LlamaguardRiskOracleRouter routes, shared by the
///         deploy/register scripts and tests so a selector is declared in exactly one place.
/// @dev Derived from the downstream interfaces rather than hand-written signature strings, so
///      a signature change surfaces as a compile error here instead of a silent selector
///      mismatch in one of the declaring files.
library RouterSelectors {
    bytes4 internal constant PUBLISH_SINGLE_SELECTOR = IRiskOracle.publishRiskParameterUpdate.selector;
    bytes4 internal constant PUBLISH_BULK_SELECTOR = IRiskOracle.publishBulkRiskParameterUpdates.selector;
    bytes4 internal constant UPDATE_LLAMAGUARD_SELECTOR = ILlamaGuardOracle.updateLatestRiskRoundData.selector;
}
