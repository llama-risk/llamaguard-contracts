// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { EACAggregatorProxy } from "./EACAggregatorProxy.sol";
import { AggregatorV2V3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV2V3Interface.sol";
import { BaseScript } from "../Base.s.sol";
import { Addresses } from "../config/Addresses.sol";
import { console2 } from "forge-std/console2.sol";

/// @title RedeployEACAggregatorProxy
/// @notice Redeploy EACAggregatorProxy with AggregatorV2V3Interface support
/// @dev The previous proxy (0x3046) only implemented AggregatorV3Interface.
///      Aave Horizon requires latestAnswer() from AggregatorInterface (V2).
///      This script deploys a new proxy that delegates both V2 and V3 methods.
contract RedeployEACAggregatorProxy is BaseScript {
    address internal constant OLD_EAC_PROXY = 0x3046553a69a4dBD2aB2AccB30Cbf7C8d8db84D79;

    /// @notice Deploy on Sepolia only
    function run() public broadcast returns (address newProxy) {
        require(block.chainid == 11_155_111, "Not on Sepolia");
        return _deploy();
    }

    /// @notice Deploy on any network (for testing)
    function runAnyNetwork() public broadcast returns (address newProxy) {
        return _deploy();
    }

    function _deploy() internal returns (address) {
        console2.log("=========================================");
        console2.log("Redeploy EACAggregatorProxy (V2V3)");
        console2.log("=========================================");
        console2.log("Chain ID:", block.chainid);
        console2.log("Broadcaster:", broadcaster);
        console2.log("Oracle:", Addresses.SEPOLIA_USTB_LLAMAGUARD_ORACLE);
        console2.log("=========================================");

        // Deploy new proxy pointing to the existing LlamaGuardOracle
        EACAggregatorProxy newProxy = new EACAggregatorProxy(Addresses.SEPOLIA_USTB_LLAMAGUARD_ORACLE);
        address newProxyAddr = address(newProxy);
        console2.log("[OK] New EACAggregatorProxy:", newProxyAddr);

        // Sanity checks
        int256 answer = newProxy.latestAnswer();
        console2.log("[OK] latestAnswer():", answer > 0 ? uint256(answer) : uint256(-answer));

        uint8 dec = newProxy.decimals();
        console2.log("[OK] decimals():", dec);

        address agg = address(newProxy.aggregator());
        require(agg == Addresses.SEPOLIA_USTB_LLAMAGUARD_ORACLE, "Aggregator mismatch");
        console2.log("[OK] aggregator():", agg);

        _logSummary(newProxyAddr);

        return newProxyAddr;
    }

    function _logSummary(address newProxyAddr) internal pure {
        console2.log("");
        console2.log("=========================================");
        console2.log("REDEPLOYMENT SUMMARY");
        console2.log("=========================================");
        console2.log("Old EACAggregatorProxy:", OLD_EAC_PROXY);
        console2.log("New EACAggregatorProxy:", newProxyAddr);
        console2.log("Underlying oracle:", Addresses.SEPOLIA_USTB_LLAMAGUARD_ORACLE);
        console2.log("");
        console2.log("NEXT STEPS:");
        console2.log("  1. Update Horizon to use new EACAggregatorProxy");
        console2.log("  2. Update docs/deployments/sepolia_ustb_integration.md");
        console2.log("  3. Deprecate old proxy (0x3046)");
        console2.log("=========================================");
    }
}
