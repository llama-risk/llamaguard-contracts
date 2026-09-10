// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { BaseScript } from "../Base.s.sol";
import { PTParameterRegistry } from "../../../src/PTParameterRegistry.sol";

/// @notice Stand-alone script for configuring a PT market in PTParameterRegistry.
///
///         Required env vars (ALL must be explicitly set — no defaults):
///         - PT_PARAMETER_REGISTRY: deployed PTParameterRegistry address
///         - PT_ASSET: PT market/asset address to configure
///         - PT_MARKET_ENABLED: boolean (true/false)
///         - PT_MODEL_VERSION: uint32
///         - PT_EMA_SPAN: uint32 (must be > 0)
///         - PT_EMA_FRESHNESS_SECONDS: uint64 (must be > 0)
///         - PT_DISCOUNT_THRESHOLD_BPS: uint64 (must be <= 10_000)
///         - PT_K_REFERENCE_ENDPOINT: uint64 (must be > 0)
///         - PT_EMODE_CATEGORY_IDS: comma-separated uint16 values (e.g., "25,26")
///
/// @dev    Matches the slimmed PtMarketParams struct (post Task 01). The registry's
///         `_validateParams` reverts unless emaSpan/emaFreshnessSeconds/kReferenceEndpoint
///         are non-zero and thresholdBps <= 10_000.
///
///         This script uses strict env var reads (no defaults) to ensure migrations
///         explicitly specify all values. Missing env vars cause a loud revert rather
///         than silently using stale defaults.
contract SetPTMarketParams is BaseScript {
    function run() public broadcast {
        address registry = vm.envAddress("PT_PARAMETER_REGISTRY");
        address market = vm.envAddress("PT_ASSET");
        PTParameterRegistry.PtMarketParams memory config = _getPtMarketConfig();

        console2.log("Setting PT market params...");
        console2.log("  registry:", registry);
        console2.log("  market:", market);
        console2.log("  enabled:", config.enabled);
        console2.log("  modelVersion:", config.modelVersion);
        console2.log("  emaSpan:", config.emaSpan);
        console2.log("  emaFreshnessSeconds:", config.emaFreshnessSeconds);
        console2.log("  thresholdBps:", config.thresholdBps);
        console2.log("  kReferenceEndpoint:", config.kReferenceEndpoint);

        PTParameterRegistry(registry).setPtMarketParams(market, config);

        console2.log("[OK] PT market params set");
    }

    function _getPtMarketConfig() internal view returns (PTParameterRegistry.PtMarketParams memory config) {
        config = PTParameterRegistry.PtMarketParams({
            enabled: vm.envBool("PT_MARKET_ENABLED"),
            modelVersion: _toUint32(vm.envUint("PT_MODEL_VERSION")),
            emaSpan: _toUint32(vm.envUint("PT_EMA_SPAN")),
            emaFreshnessSeconds: _toUint64(vm.envUint("PT_EMA_FRESHNESS_SECONDS")),
            thresholdBps: _toUint64(vm.envUint("PT_DISCOUNT_THRESHOLD_BPS")),
            kReferenceEndpoint: _toUint64(vm.envUint("PT_K_REFERENCE_ENDPOINT")),
            emodeCategoryIds: _toUint16Array(vm.envUint("PT_EMODE_CATEGORY_IDS", ","))
        });
    }

    function _toUint16Array(uint256[] memory values) internal pure returns (uint16[] memory result) {
        result = new uint16[](values.length);
        for (uint256 i = 0; i < values.length; i++) {
            require(values[i] <= type(uint16).max, "uint16 overflow");
            result[i] = uint16(values[i]);
        }
    }

    function _toUint32(uint256 value) internal pure returns (uint32) {
        require(value <= type(uint32).max, "uint32 overflow");
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint32(value);
    }

    function _toUint64(uint256 value) internal pure returns (uint64) {
        require(value <= type(uint64).max, "uint64 overflow");
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint64(value);
    }
}
