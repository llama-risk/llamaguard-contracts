// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BaseScript } from "../Base.s.sol";
import { LlamaGuardDeployConfig } from "./LlamaGuardDeployConfig.sol";
import { LlamaGuardOracle } from "../../src/LlamaGuardOracle.sol";
import { LlamaGuardOracleProxy } from "../../src/LlamaGuardOracleProxy.sol";
import { EACAggregatorProxy } from "../../src/sepolia/EACAggregatorProxy.sol";
import { console2 } from "forge-std/Test.sol";

/// @title DeployLlamaGuardOracle
/// @notice Deploys LlamaGuardOracle + Proxy (and optional EACAggregatorProxy) and wires roles
contract DeployLlamaGuardOracle is BaseScript {
    error ExpectedAuthorNotConfigured();
    error ExpectedForwarderNotConfigured();
    error ExpectedWorkflowNameNotConfigured();
    error ExpectedWorkflowIdNotConfigured();
    error ProxyOracleNotSetCorrectly();
    error AddressCannotBeZero();
    error MissingAdminRole();
    error ReplacementOracleAdminRequired();

    LlamaGuardDeployConfig internal deployConfig;

    function setUp() public {
        deployConfig = new LlamaGuardDeployConfig();
    }

    /// @notice Main deployment function with proxy setup, writer role grant and optional ownership hand-off
    function run()
        public
        broadcast
        returns (LlamaGuardOracle oracle, LlamaGuardOracleProxy proxy, EACAggregatorProxy eacProxy)
    {
        uint256 chainId = block.chainid;
        LlamaGuardDeployConfig.Config memory config = getConfig(chainId);

        console2.log("Deploying to chain ID:", chainId);
        console2.log("Network:", config.networkName);
        console2.log("Deployer (broadcaster):", broadcaster);

        if (config.expectedAuthor == address(0)) revert ExpectedAuthorNotConfigured();
        if (config.expectedForwarder == address(0)) revert ExpectedForwarderNotConfigured();
        if (config.expectedWorkflowName == bytes10(0)) revert ExpectedWorkflowNameNotConfigured();
        if (config.expectedWorkflowId == bytes32(0)) revert ExpectedWorkflowIdNotConfigured();

        console2.log("Expected author:", config.expectedAuthor);
        console2.log("Expected workflow name:", vm.toString(abi.encodePacked(config.expectedWorkflowName)));
        console2.log("Expected workflow id:", vm.toString(config.expectedWorkflowId));

        (oracle, proxy) = deployContracts(config);
        configureOracle(oracle, address(proxy));
        configureProxySecurity(proxy, config);
        finalizeAdministration(oracle, proxy, config);

        if (config.deployEacAggregator) {
            eacProxy = deployEacAggregator(oracle, config);
        } else if (config.aggregatorOwner != address(0)) {
            console2.log("");
            console2.log("[WARN] Aggregator owner provided but deployEacAggregator is disabled");
        }

        console2.log("");
        console2.log("===========================================");
        console2.log("LlamaGuard deployment completed");
        console2.log("Oracle:", address(oracle));
        console2.log("Proxy:", address(proxy));
        console2.log("Proxy owner:", proxy.owner());
        console2.log("Proxy security active:", proxy.isReportWriteSecured());
        console2.log("Broadcaster is oracle admin:", oracle.hasRole(oracle.DEFAULT_ADMIN_ROLE(), broadcaster));
        if (config.oracleAdmin != address(0)) {
            console2.log("Configured oracle admin:", config.oracleAdmin);
            console2.log(
                "Configured oracle admin has role:", oracle.hasRole(oracle.DEFAULT_ADMIN_ROLE(), config.oracleAdmin)
            );
        }
        if (address(eacProxy) != address(0)) {
            console2.log("EACAggregatorProxy:", address(eacProxy));
            console2.log("Aggregator owner:", eacProxy.owner());
        }
        console2.log("===========================================");
    }

    /// @notice Deploy the LlamaGuardOracle and LlamaGuardOracleProxy contracts
    function deployContracts(LlamaGuardDeployConfig.Config memory config)
        internal
        returns (LlamaGuardOracle oracle, LlamaGuardOracleProxy proxy)
    {
        oracle = new LlamaGuardOracle(config.decimals, config.description, config.version);
        console2.log("LlamaGuardOracle deployed at:", address(oracle));

        // Ensure broadcaster holds admin role on oracle
        if (!oracle.hasRole(oracle.DEFAULT_ADMIN_ROLE(), broadcaster)) revert MissingAdminRole();

        proxy = new LlamaGuardOracleProxy(
            address(oracle),
            config.expectedAuthor,
            config.expectedForwarder,
            config.expectedWorkflowName,
            config.expectedWorkflowId,
            config.description
        );

        console2.log("LlamaGuardOracleProxy deployed at:", address(proxy));
        console2.log("Proxy configured with:");
        console2.log("  Oracle address:", address(oracle));
        console2.log("  Expected author:", proxy.EXPECTED_AUTHOR());
        console2.log("  Expected workflow:", vm.toString(abi.encodePacked(proxy.EXPECTED_WORKFLOW_NAME())));
        console2.log("  Description:", proxy.description());

        if (address(proxy.llamaguardOracle()) != address(oracle)) revert ProxyOracleNotSetCorrectly();
    }

    /// @notice Configure the oracle to allow the proxy to write
    function configureOracle(LlamaGuardOracle oracle, address proxyAddress) internal {
        if (proxyAddress == address(0)) revert AddressCannotBeZero();
        if (oracle.hasWriteAccess(proxyAddress)) {
            console2.log("");
            console2.log("Proxy already has writer role, skipping grant");
            return;
        }

        console2.log("");
        console2.log("Configuring oracle with proxy writer role...");
        console2.log("  Granting WRITER_ROLE to:", proxyAddress);
        oracle.grantRole(oracle.WRITER_ROLE(), proxyAddress);
        console2.log("  [OK] WRITER_ROLE granted");
        require(oracle.hasWriteAccess(proxyAddress), "Writer role not set correctly");
    }

    /// @notice Optionally disable proxy security checks based on configuration
    function configureProxySecurity(
        LlamaGuardOracleProxy proxy,
        LlamaGuardDeployConfig.Config memory config
    )
        internal
    {
        if (!config.deactivateSecurity) {
            return;
        }

        if (!proxy.isReportWriteSecured()) {
            console2.log("");
            console2.log("Proxy security already deactivated, skipping");
            return;
        }

        console2.log("");
        console2.log("Disabling proxy report write security checks...");
        proxy.setIsReportWriteSecured(false);
        console2.log("  [OK] Proxy security disabled");
    }

    /// @notice Finalize administration by transferring ownership / roles per configuration
    function finalizeAdministration(
        LlamaGuardOracle oracle,
        LlamaGuardOracleProxy proxy,
        LlamaGuardDeployConfig.Config memory config
    )
        internal
    {
        if (config.revokeBroadcasterAdmin && config.oracleAdmin == address(0)) {
            revert ReplacementOracleAdminRequired();
        }

        if (config.proxyOwner != address(0) && proxy.owner() != config.proxyOwner) {
            console2.log("");
            console2.log("Transferring proxy ownership...");
            console2.log("  From:", proxy.owner());
            console2.log("  To:", config.proxyOwner);
            proxy.transferOwnership(config.proxyOwner);
            console2.log("  [OK] Proxy ownership transferred");
        }

        if (config.oracleAdmin != address(0) && !oracle.hasRole(oracle.DEFAULT_ADMIN_ROLE(), config.oracleAdmin)) {
            console2.log("");
            console2.log("Granting oracle DEFAULT_ADMIN_ROLE to:", config.oracleAdmin);
            oracle.grantRole(oracle.DEFAULT_ADMIN_ROLE(), config.oracleAdmin);
            console2.log("  [OK] Oracle admin granted");
        }

        if (config.revokeBroadcasterAdmin && oracle.hasRole(oracle.DEFAULT_ADMIN_ROLE(), broadcaster)) {
            console2.log("");
            console2.log("Renouncing broadcaster oracle admin role...");
            oracle.renounceRole(oracle.DEFAULT_ADMIN_ROLE(), broadcaster);
            console2.log("  [OK] Broadcaster admin role renounced");
        }
    }

    /// @notice Deploy an optional Chainlink-style aggregator proxy
    function deployEacAggregator(
        LlamaGuardOracle oracle,
        LlamaGuardDeployConfig.Config memory config
    )
        internal
        returns (EACAggregatorProxy eacProxy)
    {
        console2.log("");
        console2.log("Deploying EACAggregatorProxy wrapper...");
        eacProxy = new EACAggregatorProxy(address(oracle));
        console2.log("EACAggregatorProxy deployed at:", address(eacProxy));

        if (config.aggregatorOwner != address(0) && eacProxy.owner() != config.aggregatorOwner) {
            console2.log("Transferring aggregator ownership to:", config.aggregatorOwner);
            eacProxy.transferOwnership(config.aggregatorOwner);
            console2.log("  [OK] Aggregator ownership transferred");
        }
    }

    /// @notice Get configuration based on priority: env vars > chain-specific config
    function getConfig(uint256 chainId) internal view returns (LlamaGuardDeployConfig.Config memory config) {
        bool useEnvConfig = vm.envOr({ name: "USE_ENV_CONFIG", defaultValue: false });
        if (useEnvConfig) {
            console2.log("Using environment variable configuration");

            LlamaGuardDeployConfig.Config memory envConfig;

            envConfig.expectedAuthor = vm.envOr({ name: "EXPECTED_AUTHOR", defaultValue: address(0) });
            envConfig.expectedForwarder = vm.envOr({ name: "EXPECTED_FORWARDER", defaultValue: address(0) });
            envConfig.expectedWorkflowName =
                bytes10(vm.envOr({ name: "EXPECTED_WORKFLOW_NAME", defaultValue: bytes32(0) }));
            envConfig.expectedWorkflowId = vm.envOr({ name: "EXPECTED_WORKFLOW_ID", defaultValue: bytes32(0) });
            envConfig.decimals = uint8(vm.envOr({ name: "DECIMALS", defaultValue: uint256(8) }));
            envConfig.description = vm.envOr({ name: "DESCRIPTION", defaultValue: string("LlamaGuard Oracle") });
            envConfig.version = vm.envOr({ name: "VERSION", defaultValue: uint256(1) });
            envConfig.oracleAdmin = vm.envOr({ name: "ORACLE_ADMIN_ADDRESS", defaultValue: address(0) });
            envConfig.proxyOwner = vm.envOr({ name: "PROXY_OWNER_ADDRESS", defaultValue: address(0) });
            envConfig.aggregatorOwner = vm.envOr({ name: "AGGREGATOR_OWNER_ADDRESS", defaultValue: address(0) });
            envConfig.revokeBroadcasterAdmin = vm.envOr({ name: "REVOKE_BROADCASTER_ADMIN", defaultValue: false });
            envConfig.deployEacAggregator = vm.envOr({ name: "DEPLOY_EAC_AGGREGATOR", defaultValue: false });
            envConfig.deactivateSecurity = vm.envOr({ name: "DEACTIVATE_SECURITY", defaultValue: false });

            if (
                envConfig.expectedAuthor != address(0) && envConfig.expectedForwarder != address(0)
                    && envConfig.expectedWorkflowName != bytes10(0) && envConfig.expectedWorkflowId != bytes32(0)
            ) {
                string memory networkName;
                try vm.envString("NETWORK_NAME") returns (string memory name) {
                    networkName = name;
                } catch {
                    networkName = string(abi.encodePacked("chain-", vm.toString(chainId)));
                }

                envConfig.networkName = networkName;
                return envConfig;
            }
        }

        console2.log("Using chain-specific configuration");
        config = deployConfig.getConfigByChainId(chainId);
    }

    /// @notice Deploy only the contracts without configuration
    function deployOnly() public broadcast returns (LlamaGuardOracle oracle, LlamaGuardOracleProxy proxy) {
        LlamaGuardDeployConfig.Config memory config = getConfig(block.chainid);
        (oracle, proxy) = deployContracts(config);
        console2.log("Contracts deployed without granting writer role or transferring ownership");
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
