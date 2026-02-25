// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { LlamaGuardOracle } from "../../src/LlamaGuardOracle.sol";
import { LlamaGuardOracleProxy } from "../../src/LlamaGuardOracleProxy.sol";
import { BaseScript } from "../Base.s.sol";
import { Addresses } from "../config/Addresses.sol";
import { console2 } from "forge-std/console2.sol";

/// @title RedeployLlamaGuardOracleProxy
/// @notice Deploy a replacement LlamaGuardOracleProxy with address(0) forwarder (skips forwarder check)
/// @dev Points to the existing LlamaGuardOracle at Addresses.SEPOLIA_USTB_LLAMAGUARD_ORACLE.
///      Grants WRITER_ROLE to the new proxy and revokes it from the old proxy and deployer.
contract RedeployLlamaGuardOracleProxy is BaseScript {
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
        LlamaGuardOracle oracle = LlamaGuardOracle(Addresses.SEPOLIA_USTB_LLAMAGUARD_ORACLE);

        console2.log("=========================================");
        console2.log("Redeploy LlamaGuardOracleProxy (zero-forwarder)");
        console2.log("=========================================");
        console2.log("Chain ID:", block.chainid);
        console2.log("Broadcaster:", broadcaster);
        console2.log("Oracle:", address(oracle));
        console2.log("=========================================");

        // 1. Deploy new LlamaGuardOracleProxy with address(0) forwarder
        LlamaGuardOracleProxy newProxy = new LlamaGuardOracleProxy(
            address(oracle),
            0x00a9cf308e875f62fb6df1f6e1a55dd7db46384876e4059c35abd54125a9c1af,
            address(0), // skip forwarder check
            Addresses.SEPOLIA_CRE_AUTHOR,
            _creWorkflowName("llamaguard_nav_ustb_dev"),
            "LlamaGuard USTB Oracle Proxy v2 (Sepolia)"
        );
        address newProxyAddr = address(newProxy);
        console2.log("[OK] New LlamaGuardOracleProxy:", newProxyAddr);

        // 2. Grant WRITER_ROLE to the new proxy
        oracle.grantRole(oracle.WRITER_ROLE(), newProxyAddr);
        require(oracle.hasWriteAccess(newProxyAddr), "WRITER_ROLE not granted to new proxy");
        console2.log("[OK] WRITER_ROLE granted to new proxy");

        // 3. Revoke WRITER_ROLE from old proxy
        oracle.revokeRole(oracle.WRITER_ROLE(), Addresses.SEPOLIA_USTB_LLAMAGUARD_ORACLE_PROXY);
        require(
            !oracle.hasWriteAccess(Addresses.SEPOLIA_USTB_LLAMAGUARD_ORACLE_PROXY),
            "WRITER_ROLE not revoked from old proxy"
        );
        console2.log("[OK] WRITER_ROLE revoked from old proxy");

        // 4. Revoke WRITER_ROLE from deployer
        oracle.revokeRole(oracle.WRITER_ROLE(), Addresses.SEPOLIA_HOT_WALLET);
        require(!oracle.hasWriteAccess(Addresses.SEPOLIA_HOT_WALLET), "WRITER_ROLE not revoked from deployer");
        console2.log("[OK] WRITER_ROLE revoked from deployer");

        _logSummary(newProxyAddr);

        return newProxyAddr;
    }

    /// @notice Derive CRE workflow name from human-readable name
    /// @dev Mirrors SepoliaConfig._creWorkflowName() (internal, so we inline it)
    function _creWorkflowName(string memory workflowName) internal pure returns (bytes10) {
        bytes32 hash = sha256(bytes(workflowName));
        bytes memory hexChars = "0123456789abcdef";
        bytes memory result = new bytes(10);
        for (uint256 i = 0; i < 5; i++) {
            uint8 b = uint8(hash[i]);
            result[i * 2] = hexChars[b >> 4];
            result[i * 2 + 1] = hexChars[b & 0x0f];
        }
        return bytes10(bytes(result));
    }

    function _logSummary(address newProxyAddr) internal pure {
        console2.log("");
        console2.log("=========================================");
        console2.log("REDEPLOYMENT SUMMARY");
        console2.log("=========================================");
        console2.log("Old LlamaGuardOracleProxy:", Addresses.SEPOLIA_USTB_LLAMAGUARD_ORACLE_PROXY);
        console2.log("New LlamaGuardOracleProxy:", newProxyAddr);
        console2.log("Underlying oracle:", Addresses.SEPOLIA_USTB_LLAMAGUARD_ORACLE);
        console2.log("");
        console2.log("NEXT STEPS:");
        console2.log("  1. Update docs/deployments/sepolia_ustb_integration.md");
        console2.log("  2. Share new proxy address with Chainlink CRE team");
        console2.log("=========================================");
    }
}
