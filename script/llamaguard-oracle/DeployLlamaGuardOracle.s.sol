// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { LlamaGuardOracle } from "../../src/LlamaGuardOracle.sol";
import { LlamaGuardOracleProxy } from "../../src/LlamaGuardOracleProxy.sol";
import { BaseScript } from "../Base.s.sol";
import { LlamaGuardOracleConfig } from "./LlamaGuardOracleConfig.sol";
import { console2 } from "forge-std/Test.sol";

/// @title DeployLlamaGuardOracle
/// @notice Deployment script for multiple LlamaGuardOracle and LlamaGuardOracleProxy pairs
/// @dev Deployment workflow per config:
///      1. Deploy LlamaGuardOracle with configuration
///      2. Deploy LlamaGuardOracleProxy pointing to the oracle
///      3. Grant WRITER_ROLE to proxy on the oracle
///      4. Optionally transfer ownership (two-step process)
contract DeployLlamaGuardOracle is BaseScript {
    LlamaGuardOracleConfig internal config;

    /// @notice Struct to hold deployed contract addresses
    struct DeployedContracts {
        string name;
        address oracle;
        address proxy;
    }

    function setUp() public {
        config = new LlamaGuardOracleConfig();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MAIN DEPLOYMENT FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Deploy all configured oracle+proxy pairs for mainnet
    /// @dev Validates all configurations before deployment
    /// @return deployed Array of deployed contract addresses
    function run() public broadcast returns (DeployedContracts[] memory deployed) {
        require(block.chainid == 1, "DeployLlamaGuardOracle: Not on Ethereum mainnet");

        // Validate all configurations before deployment
        (bool isValid, string memory message) = config.validateMainnetConfigs();
        require(isValid, string.concat("DeployLlamaGuardOracle: Invalid config - ", message));

        return _deployAll();
    }

    /// @notice Deploy all configured oracle+proxy pairs on any network
    /// @dev For testing on non-mainnet networks
    /// @return deployed Array of deployed contract addresses
    function runAnyNetwork() public broadcast returns (DeployedContracts[] memory deployed) {
        return _deployAll();
    }

    /// @notice Deploy a single oracle+proxy pair by index
    /// @param index The index of the configuration to deploy
    /// @return oracle The deployed LlamaGuardOracle contract
    /// @return proxy The deployed LlamaGuardOracleProxy contract
    function runSingle(uint256 index) public broadcast returns (LlamaGuardOracle oracle, LlamaGuardOracleProxy proxy) {
        LlamaGuardOracleConfig.DeploymentConfig memory deployConfig = config.getConfigByIndex(block.chainid, index);

        console2.log("===========================================");
        console2.log("Deploying Single Oracle+Proxy Pair");
        console2.log("Config Index:", index);
        console2.log("Config Name:", deployConfig.oracle.name);
        console2.log("===========================================");

        (oracle, proxy) = _deploySingle(deployConfig);

        _logSingleDeployment(deployConfig.oracle.name, oracle, proxy);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL DEPLOYMENT LOGIC
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Deploy all configured oracle+proxy pairs
    function _deployAll() internal returns (DeployedContracts[] memory deployed) {
        LlamaGuardOracleConfig.DeploymentConfig[] memory configs = config.getConfigsByChainId(block.chainid);

        console2.log("===========================================");
        console2.log("LlamaGuard Oracle Deployment");
        console2.log("Chain ID:", block.chainid);
        console2.log("Number of deployments:", configs.length);
        console2.log("===========================================");

        deployed = new DeployedContracts[](configs.length);

        for (uint256 i = 0; i < configs.length; i++) {
            console2.log("");
            console2.log("-------------------------------------------");
            console2.log("Deploying config", i, ":", configs[i].oracle.name);
            console2.log("-------------------------------------------");

            (LlamaGuardOracle oracle, LlamaGuardOracleProxy proxy) = _deploySingle(configs[i]);

            deployed[i] =
                DeployedContracts({ name: configs[i].oracle.name, oracle: address(oracle), proxy: address(proxy) });
        }

        _logDeploymentSummary(deployed);
    }

    /// @notice Deploy a single oracle+proxy pair
    function _deploySingle(LlamaGuardOracleConfig.DeploymentConfig memory deployConfig)
        internal
        returns (LlamaGuardOracle oracle, LlamaGuardOracleProxy proxy)
    {
        // Step 1: Deploy oracle
        oracle = _deployOracle(deployConfig.oracle);

        // Step 2: Deploy proxy
        proxy = _deployProxy(deployConfig.proxy, address(oracle));

        // Step 3: Grant WRITER_ROLE to proxy
        _grantWriterRoleToProxy(oracle, address(proxy));

        // Step 4: Transfer ownership if configured
        if (deployConfig.pendingOwner != address(0) && deployConfig.pendingOwner != broadcaster) {
            _transferOwnership(oracle, proxy, deployConfig.pendingOwner);
        }
    }

    /// @notice Deploy a LlamaGuardOracle contract
    function _deployOracle(LlamaGuardOracleConfig.OracleConfig memory oracleConfig)
        internal
        returns (LlamaGuardOracle oracle)
    {
        console2.log("");
        console2.log("Deploying LlamaGuardOracle...");
        console2.log("  Name:", oracleConfig.name);
        console2.log("  Decimals:", oracleConfig.decimals);
        console2.log("  Description:", oracleConfig.description);
        console2.log("  Version:", oracleConfig.version);
        console2.log("  Update Types:", oracleConfig.updateTypes.length);
        for (uint256 i = 0; i < oracleConfig.updateTypes.length; i++) {
            console2.log("    -", oracleConfig.updateTypes[i]);
        }

        oracle = new LlamaGuardOracle(
            oracleConfig.decimals,
            oracleConfig.description,
            oracleConfig.version,
            oracleConfig.updateTypes,
            oracleConfig.authorizedMarkets
        );

        console2.log("  [OK] LlamaGuardOracle deployed at:", address(oracle));
    }

    /// @notice Deploy a LlamaGuardOracleProxy contract
    function _deployProxy(
        LlamaGuardOracleConfig.ProxyConfig memory proxyConfig,
        address oracleAddress
    )
        internal
        returns (LlamaGuardOracleProxy proxy)
    {
        console2.log("");
        console2.log("Deploying LlamaGuardOracleProxy...");
        console2.log("  Name:", proxyConfig.name);
        console2.log("  Oracle address:", oracleAddress);
        console2.log("  Workflow ID:", vm.toString(proxyConfig.workflowId));
        console2.log("  Expected Forwarder:", proxyConfig.expectedForwarder);
        console2.log("  Expected Author:", proxyConfig.expectedAuthor);
        console2.log("  Description:", proxyConfig.description);

        proxy = new LlamaGuardOracleProxy(
            oracleAddress,
            proxyConfig.workflowId,
            proxyConfig.expectedForwarder,
            proxyConfig.expectedAuthor,
            proxyConfig.expectedWorkflowName,
            proxyConfig.description
        );

        console2.log("  [OK] LlamaGuardOracleProxy deployed at:", address(proxy));
    }

    /// @notice Grant WRITER_ROLE to the proxy on the oracle
    function _grantWriterRoleToProxy(LlamaGuardOracle oracle, address proxyAddress) internal {
        console2.log("");
        console2.log("Granting WRITER_ROLE to proxy...");

        bytes32 writerRole = oracle.WRITER_ROLE();
        oracle.grantRole(writerRole, proxyAddress);

        require(oracle.hasWriteAccess(proxyAddress), "Failed to grant WRITER_ROLE");
        console2.log("  [OK] WRITER_ROLE granted to proxy");
    }

    /// @notice Transfer ownership of both oracle and proxy
    function _transferOwnership(LlamaGuardOracle oracle, LlamaGuardOracleProxy proxy, address newOwner) internal {
        console2.log("");
        console2.log("Transferring ownership...");
        console2.log("  New owner:", newOwner);

        // Transfer DEFAULT_ADMIN_ROLE on oracle
        bytes32 adminRole = oracle.DEFAULT_ADMIN_ROLE();
        oracle.grantRole(adminRole, newOwner);
        console2.log("  [OK] DEFAULT_ADMIN_ROLE granted to new owner on oracle");
        console2.log("  [INFO] Deployer should renounce DEFAULT_ADMIN_ROLE after new owner setup");

        // Transfer ownership on proxy (two-step)
        proxy.transferOwnership(newOwner);
        console2.log("  [OK] Ownership transfer initiated on proxy");
        console2.log("  [PENDING] New owner must call acceptOwnership() on proxy");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STANDALONE OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Deploy only oracles (without proxies)
    /// @return oracles Array of deployed oracle addresses
    function deployOraclesOnly() public broadcast returns (address[] memory oracles) {
        LlamaGuardOracleConfig.DeploymentConfig[] memory configs = config.getConfigsByChainId(block.chainid);

        console2.log("Deploying", configs.length, "LlamaGuardOracles only...");

        oracles = new address[](configs.length);
        for (uint256 i = 0; i < configs.length; i++) {
            LlamaGuardOracle oracle = _deployOracle(configs[i].oracle);
            oracles[i] = address(oracle);
        }

        console2.log("");
        console2.log("Oracles deployed. Deploy proxies separately using deployProxiesOnly()");
    }

    /// @notice Deploy proxies for existing oracles
    /// @param oracleAddresses Array of existing oracle addresses (must match config count)
    /// @return proxies Array of deployed proxy addresses
    function deployProxiesOnly(address[] calldata oracleAddresses) public broadcast returns (address[] memory proxies) {
        LlamaGuardOracleConfig.DeploymentConfig[] memory configs = config.getConfigsByChainId(block.chainid);

        require(oracleAddresses.length == configs.length, "Oracle addresses count must match config count");

        console2.log("Deploying", configs.length, "LlamaGuardOracleProxies...");

        proxies = new address[](configs.length);
        for (uint256 i = 0; i < configs.length; i++) {
            require(oracleAddresses[i] != address(0), "Oracle address cannot be zero");

            LlamaGuardOracleProxy proxy = _deployProxy(configs[i].proxy, oracleAddresses[i]);
            proxies[i] = address(proxy);
        }

        console2.log("");
        console2.log("[INFO] Remember to grant WRITER_ROLE to each proxy on its oracle");
    }

    /// @notice Grant WRITER_ROLE to proxies on existing oracles
    /// @param oracleAddresses Array of oracle addresses
    /// @param proxyAddresses Array of proxy addresses
    function grantWriterRoles(address[] calldata oracleAddresses, address[] calldata proxyAddresses) public broadcast {
        require(oracleAddresses.length == proxyAddresses.length, "Array length mismatch");

        for (uint256 i = 0; i < oracleAddresses.length; i++) {
            require(oracleAddresses[i] != address(0), "Oracle address cannot be zero");
            require(proxyAddresses[i] != address(0), "Proxy address cannot be zero");

            LlamaGuardOracle oracle = LlamaGuardOracle(oracleAddresses[i]);
            _grantWriterRoleToProxy(oracle, proxyAddresses[i]);
        }
    }

    /// @notice Add authorized markets to multiple oracles
    /// @param oracleAddresses Array of oracle addresses
    /// @param marketAddresses Array of market addresses (one per oracle)
    function addAuthorizedMarkets(
        address[] calldata oracleAddresses,
        address[] calldata marketAddresses
    )
        public
        broadcast
    {
        require(oracleAddresses.length == marketAddresses.length, "Array length mismatch");

        for (uint256 i = 0; i < oracleAddresses.length; i++) {
            require(oracleAddresses[i] != address(0), "Oracle address cannot be zero");
            require(marketAddresses[i] != address(0), "Market address cannot be zero");

            LlamaGuardOracle oracle = LlamaGuardOracle(oracleAddresses[i]);

            console2.log("Adding authorized market...");
            console2.log("  Oracle:", oracleAddresses[i]);
            console2.log("  Market:", marketAddresses[i]);

            oracle.addAuthorizedMarket(marketAddresses[i]);

            require(oracle.isAuthorizedMarket(marketAddresses[i]), "Failed to add market");
            console2.log("  [OK] Market authorized");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LOGGING HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Log deployment summary for all deployments
    function _logDeploymentSummary(DeployedContracts[] memory deployed) internal pure {
        console2.log("");
        console2.log("===========================================");
        console2.log("Deployment Summary");
        console2.log("===========================================");

        for (uint256 i = 0; i < deployed.length; i++) {
            console2.log("");
            console2.log("Config:", deployed[i].name);
            console2.log("  Oracle:", deployed[i].oracle);
            console2.log("  Proxy:", deployed[i].proxy);
        }

        console2.log("");
        console2.log("Total deployments:", deployed.length);
        console2.log("===========================================");
    }

    /// @notice Log single deployment details
    function _logSingleDeployment(
        string memory name,
        LlamaGuardOracle oracle,
        LlamaGuardOracleProxy proxy
    )
        internal
        view
    {
        console2.log("");
        console2.log("===========================================");
        console2.log("Deployment Summary:", name);
        console2.log("===========================================");
        console2.log("LlamaGuardOracle:", address(oracle));
        console2.log("  - Decimals:", oracle.decimals());
        console2.log("  - Description:", oracle.description());
        console2.log("  - Version:", oracle.version());
        console2.log("");
        console2.log("LlamaGuardOracleProxy:", address(proxy));
        console2.log("  - Owner:", proxy.owner());
        console2.log("  - Description:", proxy.description());
        console2.log("  - Has Write Access:", oracle.hasWriteAccess(address(proxy)));
        console2.log("===========================================");
    }
}
