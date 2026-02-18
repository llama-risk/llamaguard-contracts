// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { LlamaGuardOracle } from "../src/LlamaGuardOracle.sol";
import { LlamaGuardOracleProxy } from "../src/LlamaGuardOracleProxy.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { BaseScript } from "./Base.s.sol";
import { Addresses } from "./config/Addresses.sol";
import { console2 } from "forge-std/console2.sol";

/// @title TransferOwnership
/// @notice Stage 5: Transfer ownership of all contracts to final parties
/// @dev For each LlamaGuardOracle:
///      1. Grant DEFAULT_ADMIN_ROLE to new admin
///      2. Renounce DEFAULT_ADMIN_ROLE from deployer
///      For each LlamaGuardOracleProxy:
///      3. transferOwnership (two-step, new owner must acceptOwnership separately)
///      For HorizonAgentHub ProxyAdmin:
///      4. transferOwnership to Aave Horizon (single-step)
contract TransferOwnership is BaseScript {
    /// @notice Transfer ownership on mainnet
    /// @param oracleAddresses Array of LlamaGuardOracle addresses
    /// @param proxyAddresses Array of LlamaGuardOracleProxy addresses (same length)
    /// @param newAdmin The new admin address for oracles and oracle proxies
    /// @param agentHubProxyAdmin The ProxyAdmin address of HorizonAgentHub
    /// @param agentHubProxyAdminNewOwner The new owner of the AgentHub ProxyAdmin (Aave Horizon)
    function run(
        address[] calldata oracleAddresses,
        address[] calldata proxyAddresses,
        address newAdmin,
        address agentHubProxyAdmin,
        address agentHubProxyAdminNewOwner
    )
        public
        broadcast
    {
        require(block.chainid == 1, "Not on mainnet");
        _transferAll(oracleAddresses, proxyAddresses, newAdmin, agentHubProxyAdmin, agentHubProxyAdminNewOwner);
    }

    /// @notice Transfer on any network (for testing)
    function runAnyNetwork(
        address[] calldata oracleAddresses,
        address[] calldata proxyAddresses,
        address newAdmin,
        address agentHubProxyAdmin,
        address agentHubProxyAdminNewOwner
    )
        public
        broadcast
    {
        _transferAll(oracleAddresses, proxyAddresses, newAdmin, agentHubProxyAdmin, agentHubProxyAdminNewOwner);
    }

    function _transferAll(
        address[] calldata oracleAddresses,
        address[] calldata proxyAddresses,
        address newAdmin,
        address agentHubProxyAdmin,
        address agentHubProxyAdminNewOwner
    )
        internal
    {
        require(oracleAddresses.length == proxyAddresses.length, "Array length mismatch");
        require(newAdmin != address(0), "New admin cannot be zero");
        require(agentHubProxyAdminNewOwner != address(0), "AgentHub ProxyAdmin new owner cannot be zero");

        console2.log("=========================================");
        console2.log("Stage 5: Transfer Ownership");
        console2.log("=========================================");
        console2.log("Oracle/Proxy new admin:", newAdmin);
        console2.log("AgentHub ProxyAdmin new owner:", agentHubProxyAdminNewOwner);
        console2.log("Oracle pairs:", oracleAddresses.length);
        console2.log("=========================================");

        // Transfer oracle + oracle proxy ownership
        for (uint256 i = 0; i < oracleAddresses.length; ++i) {
            _transferOraclePair(oracleAddresses[i], proxyAddresses[i], newAdmin);
        }

        // Transfer AgentHub ProxyAdmin ownership to Aave Horizon
        _transferAgentHubProxyAdmin(agentHubProxyAdmin, agentHubProxyAdminNewOwner);

        console2.log("");
        console2.log("=========================================");
        console2.log("OWNERSHIP TRANSFER COMPLETE");
        console2.log("=========================================");
        console2.log("[PENDING] New owner must call acceptOwnership() on each oracle proxy");
        console2.log("[DONE] AgentHub ProxyAdmin transferred (single-step, immediate)");
        console2.log("=========================================");
    }

    function _transferOraclePair(address oracleAddress, address proxyAddress, address newAdmin) internal {
        LlamaGuardOracle oracle = LlamaGuardOracle(oracleAddress);
        LlamaGuardOracleProxy proxy = LlamaGuardOracleProxy(proxyAddress);

        string memory name = oracle.description();
        console2.log("");
        console2.log("-----------------------------------------");
        console2.log("Transferring:", name);
        console2.log("-----------------------------------------");

        // 1. Grant DEFAULT_ADMIN_ROLE to new admin on oracle
        bytes32 adminRole = oracle.DEFAULT_ADMIN_ROLE();
        oracle.grantRole(adminRole, newAdmin);
        console2.log("  [OK] DEFAULT_ADMIN_ROLE granted to new admin on oracle");

        // 2. Renounce DEFAULT_ADMIN_ROLE from deployer on oracle
        oracle.renounceRole(adminRole, broadcaster);
        console2.log("  [OK] DEFAULT_ADMIN_ROLE renounced by deployer on oracle");

        // 3. Transfer proxy ownership (two-step)
        proxy.transferOwnership(newAdmin);
        console2.log("  [OK] Oracle proxy ownership transfer initiated");
        console2.log("  [PENDING] New owner must call acceptOwnership()");
    }

    function _transferAgentHubProxyAdmin(address proxyAdminAddress, address newOwner) internal {
        console2.log("");
        console2.log("-----------------------------------------");
        console2.log("Transferring: AgentHub ProxyAdmin");
        console2.log("-----------------------------------------");

        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);
        console2.log("  Current owner:", proxyAdmin.owner());

        proxyAdmin.transferOwnership(newOwner);
        console2.log("  [OK] ProxyAdmin ownership transferred to:", newOwner);
    }
}
