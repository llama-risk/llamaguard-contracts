// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BaseScript } from "./Base.s.sol";
import { LlamaGuardDeployConfig } from "./LlamaGuardDeployConfig.sol";
import { LlamaGuardOracle } from "../src/LlamaGuardOracle.sol";
import { LlamaGuardOracleProxy } from "../src/LlamaGuardOracleProxy.sol";
import { EACAggregatorProxy } from "../src/sepolia/EACAggregatorProxy.sol";
import { console2 } from "forge-std/Test.sol";

/// @title DeployLlamaGuardOracle
/// @notice Deploys LlamaGuardOracle + Proxy and wires roles
contract DeployLlamaGuardOracle is BaseScript {
    error ExpectedAuthorNotConfigured();
    error ExpectedWorkflowNameNotConfigured();
    error ProxyOracleNotSetCorrectly();
    error AddressCannotBeZero();
    error MissingAdminRole();

    LlamaGuardDeployConfig internal deployConfig;

    function setUp() public {
        deployConfig = new LlamaGuardDeployConfig();
    }

    /// @notice Main deployment function with proxy setup and writer role grant
    function run()
        public
        broadcast
        returns (LlamaGuardOracle oracle, LlamaGuardOracleProxy proxy, EACAggregatorProxy eacProxy)
    {
        (oracle, proxy) = deployContracts();
        configureOracle(oracle, address(proxy));

        if (block.chainid == 11_155_111) {
            eacProxy = new EACAggregatorProxy(address(oracle));
            console2.log("EACAggregatorProxy deployed at:", address(eacProxy));
        }
    }

    /// @notice Deploy the LlamaGuardOracle and LlamaGuardOracleProxy contracts
    function deployContracts() internal returns (LlamaGuardOracle oracle, LlamaGuardOracleProxy proxy) {
        uint256 chainId = block.chainid;
        console2.log("Deploying to chain ID:", chainId);

        LlamaGuardDeployConfig.Config memory config = getConfig(chainId);
        if (config.expectedAuthor == address(0)) revert ExpectedAuthorNotConfigured();
        if (config.expectedWorkflowName == bytes10(0)) revert ExpectedWorkflowNameNotConfigured();

        console2.log("Network:", config.networkName);
        console2.log("Deployer (admin):", broadcaster);
        console2.log("Expected Author:", config.expectedAuthor);
        console2.log("Expected Workflow:", vm.toString(abi.encodePacked(config.expectedWorkflowName)));

        oracle = new LlamaGuardOracle(config.decimals, config.description, config.version);
        console2.log("LlamaGuardOracle deployed at:", address(oracle));

        // Ensure broadcaster holds admin role on oracle
        if (!oracle.hasRole(oracle.DEFAULT_ADMIN_ROLE(), broadcaster)) revert MissingAdminRole();

        proxy = new LlamaGuardOracleProxy(
            address(oracle),
            config.expectedAuthor,
            config.expectedWorkflowName,
            config.description
        );

        console2.log("LlamaGuardOracleProxy deployed at:", address(proxy));
        console2.log("Proxy configured with:");
        console2.log("  Oracle address:", address(oracle));
        console2.log("  Expected author:", proxy.EXPECTED_AUTHOR());
        console2.log("  Expected workflow:", vm.toString(abi.encodePacked(proxy.EXPECTED_WORKFLOW_NAME())));
        console2.log("  Proxy description:", proxy.description());

        if (address(proxy.llamaguardOracle()) != address(oracle)) revert ProxyOracleNotSetCorrectly();
    }

    /// @notice Configure the oracle to allow the proxy to write
    function configureOracle(LlamaGuardOracle oracle, address proxyAddress) internal {
        if (proxyAddress == address(0)) revert AddressCannotBeZero();
        console2.log("");
        console2.log("Configuring oracle with proxy writer role...");
        console2.log("  Granting WRITER_ROLE to:", proxyAddress);
        oracle.grantRole(oracle.WRITER_ROLE(), proxyAddress);
        console2.log("  [OK] WRITER_ROLE granted");
        require(oracle.hasWriteAccess(proxyAddress), "Writer role not set correctly");
    }

    /// @notice Get configuration based on priority: env vars > chain-specific config
    function getConfig(uint256 chainId) internal view returns (LlamaGuardDeployConfig.Config memory config) {
        bool useEnvConfig = vm.envOr({ name: "USE_ENV_CONFIG", defaultValue: false });
        if (useEnvConfig) {
            console2.log("Using environment variable configuration");

            address expectedAuthor = vm.envOr({ name: "EXPECTED_AUTHOR", defaultValue: address(0) });
            bytes32 workflowNameBytes = vm.envOr({ name: "EXPECTED_WORKFLOW_NAME", defaultValue: bytes32(0) });
            bytes10 expectedWorkflowName = bytes10(workflowNameBytes);
            uint8 decimals = uint8(vm.envOr({ name: "DECIMALS", defaultValue: uint256(8) }));
            string memory description = vm.envOr({ name: "DESCRIPTION", defaultValue: string("LlamaGuard Oracle") });
            uint256 version = vm.envOr({ name: "VERSION", defaultValue: uint256(1) });

            if (expectedAuthor != address(0) && expectedWorkflowName != bytes10(0)) {
                string memory networkName;
                try vm.envString("NETWORK_NAME") returns (string memory name) {
                    networkName = name;
                } catch {
                    networkName = string(abi.encodePacked("chain-", vm.toString(chainId)));
                }

                config = LlamaGuardDeployConfig.Config({
                    expectedAuthor: expectedAuthor,
                    expectedWorkflowName: expectedWorkflowName,
                    decimals: decimals,
                    description: description,
                    version: version,
                    pendingOwner: address(0),
                    networkName: networkName
                });
                return config;
            }
        }

        console2.log("Using chain-specific configuration");
        config = deployConfig.getConfigByChainId(chainId);
    }

    /// @notice Deploy only the contracts without configuration
    function deployOnly() public broadcast returns (LlamaGuardOracle oracle, LlamaGuardOracleProxy proxy) {
        (oracle, proxy) = deployContracts();
        console2.log("Contracts deployed without configuration");
        console2.log("To configure, call configureManually() separately");
    }

    /// @notice Configure an already deployed oracle with an existing proxy
    function configureManually(address oracleAddress, address proxyAddress) public broadcast {
        if (oracleAddress == address(0)) revert AddressCannotBeZero();
        if (proxyAddress == address(0)) revert AddressCannotBeZero();
        LlamaGuardOracle oracle = LlamaGuardOracle(oracleAddress);
        if (!oracle.hasRole(oracle.DEFAULT_ADMIN_ROLE(), broadcaster)) revert MissingAdminRole();
        console2.log("Configuring oracle at:", oracleAddress);
        configureOracle(oracle, proxyAddress);
    }
}

