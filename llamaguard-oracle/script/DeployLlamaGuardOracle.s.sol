// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BaseScript } from "./Base.s.sol";
import { DeployConfig } from "./DeployConfig.sol";
import { LlamaGuardOracle } from "../src/LlamaGuardOracle.sol";
import { LlamaGuardOracleProxy } from "../src/LlamaGuardOracleProxy.sol";
import { EACAggregatorProxy } from "../src/EACAggregatorProxy.sol";
import { console2 } from "forge-std/console2.sol";

/// @title DeployLlamaGuardOracle
/// @notice Universal deployment script for LlamaGuardOracle with proxy and ownership transfer
/// @dev Supports deployment to Ethereum mainnet, Sepolia, and local Anvil networks
contract DeployLlamaGuardOracle is BaseScript {
    error ExpectedAuthorNotConfigured();
    error ExpectedWorkflowNameNotConfigured();
    error OwnerNotSetCorrectly();
    error ProxyOracleNotSetCorrectly();
    error ProxyAddressNotSetCorrectly();
    error PendingOwnerNotSetCorrectly();
    error AddressCannotBeZero();
    error CallerIsNotOwner();

    DeployConfig internal deployConfig;

    function setUp() public {
        deployConfig = new DeployConfig();
    }

    /// @notice Main deployment function with proxy setup and optional ownership transfer
    /// @return oracle The deployed LlamaGuardOracle contract
    /// @return proxy The deployed LlamaGuardOracleProxy contract
    /// @return eacProxy The deployed EACAggregatorProxy (Sepolia only, otherwise address(0))
    function run()
        public
        broadcast
        returns (LlamaGuardOracle oracle, LlamaGuardOracleProxy proxy, EACAggregatorProxy eacProxy)
    {
        // Deploy the oracle and proxy
        (oracle, proxy) = deployContracts();

        // Configure the oracle with proxy
        configureOracle(oracle, address(proxy));

        // Deploy EACAggregatorProxy on Sepolia for testing
        if (block.chainid == 11_155_111) {
            // Sepolia
            eacProxy = deployEACAggregatorProxy(oracle);
        }

        // Transfer ownership if configured
        transferOwnershipIfNeeded(oracle);
    }

    /// @notice Deploy the LlamaGuardOracle and LlamaGuardOracleProxy contracts
    /// @return oracle The deployed oracle contract
    /// @return proxy The deployed proxy contract
    function deployContracts() internal returns (LlamaGuardOracle oracle, LlamaGuardOracleProxy proxy) {
        // Get the current chain ID
        uint256 chainId = block.chainid;
        console2.log("Deploying to chain ID:", chainId);

        // Get configuration based on deployment method
        DeployConfig.Config memory config = getConfig(chainId);

        // Validate configuration
        if (config.expectedAuthor == address(0)) revert ExpectedAuthorNotConfigured();
        if (config.expectedWorkflowName == bytes10(0)) revert ExpectedWorkflowNameNotConfigured();

        // Log deployment parameters
        console2.log("Network:", config.networkName);
        console2.log("Deployer (initial owner):", broadcaster);
        console2.log("Expected Author:", config.expectedAuthor);
        console2.log("Expected Workflow:", vm.toString(abi.encodePacked(config.expectedWorkflowName)));

        // Deploy the oracle
        oracle = new LlamaGuardOracle(config.decimals, config.description, config.version);

        console2.log("LlamaGuardOracle deployed at:", address(oracle));
        console2.log("Initial owner:", oracle.owner());

        // Deploy the proxy
        proxy = new LlamaGuardOracleProxy(address(oracle), config.expectedAuthor, config.expectedWorkflowName);

        console2.log("LlamaGuardOracleProxy deployed at:", address(proxy));
        console2.log("Proxy configured with:");
        console2.log("  Oracle address:", address(oracle));
        console2.log("  Expected author:", proxy.EXPECTED_AUTHOR());
        console2.log("  Expected workflow:", vm.toString(abi.encodePacked(proxy.EXPECTED_WORKFLOW_NAME())));

        // Verify deployment
        if (oracle.owner() != broadcaster) revert OwnerNotSetCorrectly();
        if (address(proxy.s_llamaGuardOracle()) != address(oracle)) revert ProxyOracleNotSetCorrectly();
    }

    /// @notice Configure the oracle with the proxy address
    /// @param oracle The deployed oracle contract
    /// @param proxyAddress The address of the deployed proxy
    function configureOracle(LlamaGuardOracle oracle, address proxyAddress) internal {
        console2.log("");
        console2.log("Configuring oracle with proxy...");
        console2.log("  Setting proxy address:", proxyAddress);

        oracle.setProxyAddress(proxyAddress);

        console2.log("  [OK] Proxy address configured");
        if (oracle.proxyAddress() != proxyAddress) revert ProxyAddressNotSetCorrectly();
    }

    /// @notice Deploy an EACAggregatorProxy pointing to the oracle (for testing on Sepolia)
    /// @param oracle The deployed oracle contract
    /// @return eacProxy The deployed EACAggregatorProxy
    function deployEACAggregatorProxy(LlamaGuardOracle oracle) internal returns (EACAggregatorProxy eacProxy) {
        console2.log("");
        console2.log("Deploying EACAggregatorProxy for testing...");
        console2.log("  Pointing to oracle:", address(oracle));

        eacProxy = new EACAggregatorProxy(address(oracle));

        console2.log("  [OK] EACAggregatorProxy deployed at:", address(eacProxy));
        console2.log("  Initial owner:", eacProxy.owner());
        console2.log("  Aggregator:", address(eacProxy.aggregator()));

        // Verify the proxy points to the oracle
        require(address(eacProxy.aggregator()) == address(oracle), "EAC proxy not pointing to oracle");

        console2.log("");
        console2.log("===========================================");
        console2.log("Testing Setup (Sepolia)");
        console2.log("===========================================");
        console2.log("Use this address for Chainlink-compatible consumers:");
        console2.log("EACAggregatorProxy:", address(eacProxy));
        console2.log("===========================================");
    }

    /// @notice Transfer ownership if configured
    /// @param oracle The deployed oracle contract
    function transferOwnershipIfNeeded(LlamaGuardOracle oracle) internal {
        uint256 chainId = block.chainid;
        DeployConfig.Config memory config = getConfig(chainId);

        // Initiate ownership transfer (two-step process) if configured
        if (config.pendingOwner != address(0) && config.pendingOwner != broadcaster) {
            console2.log("");
            console2.log("Initiating ownership transfer (two-step process)...");
            console2.log("  Current owner:", broadcaster);
            console2.log("  Pending owner:", config.pendingOwner);

            oracle.transferOwnership(config.pendingOwner);

            console2.log("  [OK] Ownership transfer initiated");
            console2.log("  [PENDING] New owner must call acceptOwnership() to complete transfer");

            if (oracle.pendingOwner() != config.pendingOwner) revert PendingOwnerNotSetCorrectly();

            console2.log("");
            console2.log("===========================================");
            console2.log("Deployment completed with ownership transfer!");
            console2.log("===========================================");
            console2.log("LlamaGuardOracle:", address(oracle));
            console2.log("LlamaGuardOracleProxy:", address(oracle.proxyAddress()));
            console2.log("Current owner:", oracle.owner());
            console2.log("Pending owner:", oracle.pendingOwner());
            console2.log("IMPORTANT: Pending owner must call acceptOwnership()");
            console2.log("===========================================");
        } else {
            console2.log("");
            console2.log("===========================================");
            console2.log("Deployment completed successfully!");
            console2.log("===========================================");
            console2.log("LlamaGuardOracle:", address(oracle));
            console2.log("LlamaGuardOracleProxy:", address(oracle.proxyAddress()));
            console2.log("Owner:", oracle.owner());
            console2.log("===========================================");
        }
    }

    /// @notice Get configuration based on priority: env vars > chain-specific config
    /// @param chainId The chain ID of the target network
    /// @return config The deployment configuration
    function getConfig(uint256 chainId) internal view returns (DeployConfig.Config memory config) {
        // First, try to get configuration from environment variables
        bool useEnvConfig = vm.envOr({ name: "USE_ENV_CONFIG", defaultValue: false });

        if (useEnvConfig) {
            console2.log("Using environment variable configuration");

            address expectedAuthor = vm.envOr({ name: "EXPECTED_AUTHOR", defaultValue: address(0) });
            bytes32 workflowNameBytes = vm.envOr({ name: "EXPECTED_WORKFLOW_NAME", defaultValue: bytes32(0) });
            bytes10 expectedWorkflowName = bytes10(workflowNameBytes);
            uint8 decimals = uint8(vm.envOr({ name: "DECIMALS", defaultValue: uint256(8) }));
            string memory description = vm.envOr({ name: "DESCRIPTION", defaultValue: string("LlamaGuard Oracle") });
            uint256 version = vm.envOr({ name: "VERSION", defaultValue: uint256(1) });
            address pendingOwner = vm.envOr({ name: "PENDING_OWNER", defaultValue: address(0) });

            // If env vars are set, use them
            if (expectedAuthor != address(0) && expectedWorkflowName != bytes10(0)) {
                string memory networkName;
                try vm.envString("NETWORK_NAME") returns (string memory name) {
                    networkName = name;
                } catch {
                    networkName = string(abi.encodePacked("chain-", vm.toString(chainId)));
                }

                config = DeployConfig.Config({
                    expectedAuthor: expectedAuthor,
                    expectedWorkflowName: expectedWorkflowName,
                    decimals: decimals,
                    description: description,
                    version: version,
                    pendingOwner: pendingOwner,
                    networkName: networkName
                });
                return config;
            }
        }

        // Otherwise, use chain-specific configuration
        console2.log("Using chain-specific configuration");
        config = deployConfig.getConfigByChainId(chainId);
    }

    /// @notice Deploy only the contracts without configuration
    /// @dev Useful when you want to deploy but configure separately
    function deployOnly() public broadcast returns (LlamaGuardOracle oracle, LlamaGuardOracleProxy proxy) {
        (oracle, proxy) = deployContracts();
        console2.log("Contracts deployed without configuration");
        console2.log("To configure, call configureManually() separately");
    }

    /// @notice Configure an already deployed oracle
    /// @dev Can be called separately after deployment if needed
    /// @param oracleAddress The address of the deployed LlamaGuardOracle
    /// @param proxyAddress The address of the deployed LlamaGuardOracleProxy
    function configureManually(address oracleAddress, address proxyAddress) public broadcast {
        if (oracleAddress == address(0)) revert AddressCannotBeZero();
        if (proxyAddress == address(0)) revert AddressCannotBeZero();

        LlamaGuardOracle oracle = LlamaGuardOracle(oracleAddress);

        // Verify the oracle is valid and we have owner permissions
        if (oracle.owner() != broadcaster) revert CallerIsNotOwner();

        console2.log("Configuring oracle at:", oracleAddress);
        configureOracle(oracle, proxyAddress);
    }

    /// @notice Transfer ownership on an already deployed oracle
    /// @dev Can be called separately after deployment and configuration
    /// @param oracleAddress The address of the deployed LlamaGuardOracle
    function transferOwnershipManually(address oracleAddress) public broadcast {
        if (oracleAddress == address(0)) revert AddressCannotBeZero();

        LlamaGuardOracle oracle = LlamaGuardOracle(oracleAddress);

        // Verify the oracle is valid and we have owner permissions
        if (oracle.owner() != broadcaster) revert CallerIsNotOwner();

        console2.log("Transferring ownership on oracle at:", oracleAddress);
        transferOwnershipIfNeeded(oracle);
    }
}

