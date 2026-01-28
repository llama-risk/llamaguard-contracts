// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { Test } from "forge-std/Test.sol";
import { LlamaGuardOracle } from "../../src/LlamaGuardOracle.sol";
import { LlamaGuardOracleProxy } from "../../src/LlamaGuardOracleProxy.sol";
import { DeployLlamaGuardOracle } from "../../script/llamaguard-oracle/DeployLlamaGuardOracle.s.sol";
import { LlamaGuardOracleConfig } from "../../script/llamaguard-oracle/LlamaGuardOracleConfig.sol";

/// @title DeployLlamaGuardOracleTest
/// @notice Comprehensive test suite for LlamaGuardOracle deployment scripts
contract DeployLlamaGuardOracleTest is Test {
    DeployLlamaGuardOracle internal deployScript;
    LlamaGuardOracleConfig internal config;

    address internal deployer;
    address internal pendingOwner;
    address internal unauthorizedUser;

    function setUp() public {
        // Set up deployer address using ETH_FROM like in existing tests
        vm.setEnv("ETH_FROM", "0x0000000000000000000000000000000000000aBc");
        deployer = address(0x0000000000000000000000000000000000000aBc);

        pendingOwner = makeAddr("pendingOwner");
        unauthorizedUser = makeAddr("unauthorizedUser");

        // Deploy scripts and config
        deployScript = new DeployLlamaGuardOracle();
        config = new LlamaGuardOracleConfig();

        // Setup script
        deployScript.setUp();

        // Fund deployer
        vm.deal(deployer, 10 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONFIG TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Config_MainnetConfigsExist() public view {
        LlamaGuardOracleConfig.DeploymentConfig[] memory configs = config.getMainnetConfigs();
        assertGt(configs.length, 0, "Should have mainnet configs");
    }

    function test_Config_SepoliaConfigsExist() public view {
        LlamaGuardOracleConfig.DeploymentConfig[] memory configs = config.getSepoliaConfigs();
        assertGt(configs.length, 0, "Should have Sepolia configs");
    }

    function test_Config_AnvilConfigsExist() public view {
        LlamaGuardOracleConfig.DeploymentConfig[] memory configs = config.getAnvilConfigs();
        assertEq(configs.length, 2, "Anvil should have 2 configs");
    }

    function test_Config_GetConfigsByChainId_Mainnet() public view {
        LlamaGuardOracleConfig.DeploymentConfig[] memory configs = config.getConfigsByChainId(1);
        assertGt(configs.length, 0, "Should return mainnet configs");
    }

    function test_Config_GetConfigsByChainId_Sepolia() public view {
        LlamaGuardOracleConfig.DeploymentConfig[] memory configs = config.getConfigsByChainId(11_155_111);
        assertGt(configs.length, 0, "Should return Sepolia configs");
    }

    function test_Config_GetConfigsByChainId_Anvil() public view {
        LlamaGuardOracleConfig.DeploymentConfig[] memory configs = config.getConfigsByChainId(31_337);
        assertEq(configs.length, 2, "Should return Anvil configs");
    }

    function test_Config_GetConfigsByChainId_Unsupported_Reverts() public {
        vm.expectRevert(LlamaGuardOracleConfig.UnsupportedChainId.selector);
        config.getConfigsByChainId(999_999);
    }

    function test_Config_HasConfigsForChain() public view {
        assertTrue(config.hasConfigsForChain(1), "Should have mainnet configs");
        assertTrue(config.hasConfigsForChain(11_155_111), "Should have Sepolia configs");
        assertTrue(config.hasConfigsForChain(31_337), "Should have Anvil configs");
        assertFalse(config.hasConfigsForChain(999_999), "Should not have configs for unknown chain");
    }

    function test_Config_GetConfigCount() public view {
        assertEq(config.getConfigCount(1), 1, "Mainnet should have 1 config");
        assertEq(config.getConfigCount(11_155_111), 2, "Sepolia should have 2 configs");
        assertEq(config.getConfigCount(31_337), 2, "Anvil should have 2 configs");
    }

    function test_Config_GetConfigByIndex() public view {
        LlamaGuardOracleConfig.DeploymentConfig memory anvilConfig0 = config.getConfigByIndex(31_337, 0);
        assertEq(anvilConfig0.oracle.name, "TEST1", "First Anvil config should be TEST1");

        LlamaGuardOracleConfig.DeploymentConfig memory anvilConfig1 = config.getConfigByIndex(31_337, 1);
        assertEq(anvilConfig1.oracle.name, "TEST2", "Second Anvil config should be TEST2");
    }

    function test_Config_GetConfigByIndex_OutOfBounds_Reverts() public {
        vm.expectRevert("LlamaGuardOracleConfig: Index out of bounds");
        config.getConfigByIndex(31_337, 99);
    }

    function test_Config_ValidateMainnetConfigs_Incomplete() public view {
        // Mainnet configs have TODO placeholders, so validation should fail
        (bool isValid, string memory message) = config.validateMainnetConfigs();
        assertFalse(isValid, "Mainnet configs should be invalid (TODO placeholders)");
        assertGt(bytes(message).length, 0, "Should have error message");
    }

    function test_Config_ValidateConfigByIndex_Anvil() public view {
        // Anvil configs should be valid (they have test values set)
        (bool isValid, string memory message) = config.validateConfigByIndex(31_337, 0);
        assertTrue(isValid, "Anvil config 0 should be valid");
        assertEq(message, "Configuration valid", "Should have valid message");
    }

    function test_Config_AnvilConfigValues() public view {
        LlamaGuardOracleConfig.DeploymentConfig memory cfg = config.getConfigByIndex(31_337, 0);

        // Oracle config
        assertEq(cfg.oracle.name, "TEST1");
        assertEq(cfg.oracle.decimals, 8);
        assertEq(cfg.oracle.version, 1);
        assertEq(cfg.oracle.updateTypes.length, 1);
        assertEq(cfg.oracle.updateTypes[0], "boundedNAV");

        // Proxy config
        assertEq(cfg.proxy.name, "TEST1");
        assertEq(cfg.proxy.workflowId, keccak256("test-workflow-1"));
        assertEq(cfg.proxy.expectedForwarder, 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        assertEq(cfg.proxy.expectedAuthor, 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        assertEq(cfg.proxy.expectedWorkflowName, bytes10("testwork01"));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DEPLOYMENT TESTS - ANVIL
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Deployment_RunAnyNetwork_Anvil() public {
        vm.chainId(31_337);

        DeployLlamaGuardOracle.DeployedContracts[] memory deployed = deployScript.runAnyNetwork();

        assertEq(deployed.length, 2, "Should deploy 2 oracle+proxy pairs on Anvil");

        // Verify first deployment
        assertEq(deployed[0].name, "TEST1");
        assertNotEq(deployed[0].oracle, address(0), "Oracle should be deployed");
        assertNotEq(deployed[0].proxy, address(0), "Proxy should be deployed");

        // Verify second deployment
        assertEq(deployed[1].name, "TEST2");
        assertNotEq(deployed[1].oracle, address(0), "Oracle should be deployed");
        assertNotEq(deployed[1].proxy, address(0), "Proxy should be deployed");
    }

    function test_Deployment_RunAnyNetwork_OracleConfiguration() public {
        vm.chainId(31_337);

        DeployLlamaGuardOracle.DeployedContracts[] memory deployed = deployScript.runAnyNetwork();

        // Check first oracle configuration
        LlamaGuardOracle oracle1 = LlamaGuardOracle(deployed[0].oracle);
        assertEq(oracle1.decimals(), 8, "Oracle1 decimals should be 8");
        assertEq(oracle1.version(), 1, "Oracle1 version should be 1");
        assertEq(oracle1.description(), "LlamaGuard Risk Oracle 1 (Local)");

        // Check second oracle configuration
        LlamaGuardOracle oracle2 = LlamaGuardOracle(deployed[1].oracle);
        assertEq(oracle2.decimals(), 18, "Oracle2 decimals should be 18");
        assertEq(oracle2.version(), 1, "Oracle2 version should be 1");
        assertEq(oracle2.description(), "LlamaGuard Risk Oracle 2 (Local)");
    }

    function test_Deployment_RunAnyNetwork_ProxyConfiguration() public {
        vm.chainId(31_337);

        DeployLlamaGuardOracle.DeployedContracts[] memory deployed = deployScript.runAnyNetwork();

        // Check first proxy configuration
        LlamaGuardOracleProxy proxy1 = LlamaGuardOracleProxy(deployed[0].proxy);
        assertEq(proxy1.description(), "LlamaGuard Oracle Proxy 1 (Local)");
        assertEq(address(proxy1.llamaguardOracle()), deployed[0].oracle, "Proxy1 should point to oracle1");

        // Check second proxy configuration
        LlamaGuardOracleProxy proxy2 = LlamaGuardOracleProxy(deployed[1].proxy);
        assertEq(proxy2.description(), "LlamaGuard Oracle Proxy 2 (Local)");
        assertEq(address(proxy2.llamaguardOracle()), deployed[1].oracle, "Proxy2 should point to oracle2");
    }

    function test_Deployment_RunAnyNetwork_ProxyHasWriteAccess() public {
        vm.chainId(31_337);

        DeployLlamaGuardOracle.DeployedContracts[] memory deployed = deployScript.runAnyNetwork();

        // Verify proxies have WRITER_ROLE on their oracles
        LlamaGuardOracle oracle1 = LlamaGuardOracle(deployed[0].oracle);
        assertTrue(oracle1.hasWriteAccess(deployed[0].proxy), "Proxy1 should have write access to oracle1");

        LlamaGuardOracle oracle2 = LlamaGuardOracle(deployed[1].oracle);
        assertTrue(oracle2.hasWriteAccess(deployed[1].proxy), "Proxy2 should have write access to oracle2");
    }

    function test_Deployment_RunSingle() public {
        vm.chainId(31_337);

        (LlamaGuardOracle oracle, LlamaGuardOracleProxy proxy) = deployScript.runSingle(0);

        assertNotEq(address(oracle), address(0), "Oracle should be deployed");
        assertNotEq(address(proxy), address(0), "Proxy should be deployed");
        assertEq(address(proxy.llamaguardOracle()), address(oracle), "Proxy should point to oracle");
        assertTrue(oracle.hasWriteAccess(address(proxy)), "Proxy should have write access");
    }

    function test_Deployment_RunSingle_SecondConfig() public {
        vm.chainId(31_337);

        (LlamaGuardOracle oracle, LlamaGuardOracleProxy proxy) = deployScript.runSingle(1);

        assertEq(oracle.decimals(), 18, "Second config should have 18 decimals");
        assertEq(oracle.description(), "LlamaGuard Risk Oracle 2 (Local)");
        assertEq(proxy.description(), "LlamaGuard Oracle Proxy 2 (Local)");
    }

    function test_Deployment_Run_MainnetRequiresValidConfig() public {
        vm.chainId(1);

        // Should revert because mainnet configs have TODO placeholders
        vm.expectRevert();
        deployScript.run();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STANDALONE OPERATIONS TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_DeployOraclesOnly() public {
        vm.chainId(31_337);

        address[] memory oracles = deployScript.deployOraclesOnly();

        assertEq(oracles.length, 2, "Should deploy 2 oracles");
        assertNotEq(oracles[0], address(0), "Oracle1 should be deployed");
        assertNotEq(oracles[1], address(0), "Oracle2 should be deployed");

        // Verify oracle configurations
        LlamaGuardOracle oracle1 = LlamaGuardOracle(oracles[0]);
        assertEq(oracle1.decimals(), 8);

        LlamaGuardOracle oracle2 = LlamaGuardOracle(oracles[1]);
        assertEq(oracle2.decimals(), 18);
    }

    function test_DeployProxiesOnly() public {
        vm.chainId(31_337);

        // First deploy oracles
        address[] memory oracles = deployScript.deployOraclesOnly();

        // Then deploy proxies
        address[] memory proxies = deployScript.deployProxiesOnly(oracles);

        assertEq(proxies.length, 2, "Should deploy 2 proxies");
        assertNotEq(proxies[0], address(0), "Proxy1 should be deployed");
        assertNotEq(proxies[1], address(0), "Proxy2 should be deployed");

        // Verify proxy configurations
        LlamaGuardOracleProxy proxy1 = LlamaGuardOracleProxy(proxies[0]);
        assertEq(address(proxy1.llamaguardOracle()), oracles[0]);

        LlamaGuardOracleProxy proxy2 = LlamaGuardOracleProxy(proxies[1]);
        assertEq(address(proxy2.llamaguardOracle()), oracles[1]);
    }

    function test_DeployProxiesOnly_ArrayMismatch_Reverts() public {
        vm.chainId(31_337);

        // Try to deploy proxies with wrong number of oracle addresses
        address[] memory wrongOracles = new address[](1);
        wrongOracles[0] = makeAddr("oracle");

        vm.expectRevert("Oracle addresses count must match config count");
        deployScript.deployProxiesOnly(wrongOracles);
    }

    function test_DeployProxiesOnly_ZeroAddress_Reverts() public {
        vm.chainId(31_337);

        address[] memory oracles = new address[](2);
        oracles[0] = address(0); // Zero address
        oracles[1] = makeAddr("oracle2");

        vm.expectRevert("Oracle address cannot be zero");
        deployScript.deployProxiesOnly(oracles);
    }

    function test_GrantWriterRoles() public {
        vm.chainId(31_337);

        // Deploy oracles
        address[] memory oracles = deployScript.deployOraclesOnly();

        // Deploy proxies
        address[] memory proxies = deployScript.deployProxiesOnly(oracles);

        // Grant writer roles
        deployScript.grantWriterRoles(oracles, proxies);

        // Verify
        LlamaGuardOracle oracle1 = LlamaGuardOracle(oracles[0]);
        assertTrue(oracle1.hasWriteAccess(proxies[0]), "Proxy1 should have write access");

        LlamaGuardOracle oracle2 = LlamaGuardOracle(oracles[1]);
        assertTrue(oracle2.hasWriteAccess(proxies[1]), "Proxy2 should have write access");
    }

    function test_GrantWriterRoles_ArrayMismatch_Reverts() public {
        vm.chainId(31_337);

        address[] memory oracles = new address[](2);
        oracles[0] = makeAddr("oracle1");
        oracles[1] = makeAddr("oracle2");

        address[] memory proxies = new address[](1);
        proxies[0] = makeAddr("proxy1");

        vm.expectRevert("Array length mismatch");
        deployScript.grantWriterRoles(oracles, proxies);
    }

    function test_AddAuthorizedMarkets() public {
        vm.chainId(31_337);

        // Deploy oracles
        address[] memory oracles = deployScript.deployOraclesOnly();

        // Create market addresses
        address[] memory markets = new address[](2);
        markets[0] = makeAddr("market1");
        markets[1] = makeAddr("market2");

        // Add authorized markets
        deployScript.addAuthorizedMarkets(oracles, markets);

        // Verify
        LlamaGuardOracle oracle1 = LlamaGuardOracle(oracles[0]);
        assertTrue(oracle1.isAuthorizedMarket(markets[0]), "Market1 should be authorized on oracle1");

        LlamaGuardOracle oracle2 = LlamaGuardOracle(oracles[1]);
        assertTrue(oracle2.isAuthorizedMarket(markets[1]), "Market2 should be authorized on oracle2");
    }

    function test_AddAuthorizedMarkets_ZeroAddress_Reverts() public {
        vm.chainId(31_337);

        address[] memory oracles = deployScript.deployOraclesOnly();

        address[] memory markets = new address[](2);
        markets[0] = address(0); // Zero address
        markets[1] = makeAddr("market2");

        vm.expectRevert("Market address cannot be zero");
        deployScript.addAuthorizedMarkets(oracles, markets);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // OWNERSHIP TRANSFER TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Deployment_OwnershipTransfer() public {
        vm.chainId(31_337);

        // Deploy with standard config (no pending owner)
        DeployLlamaGuardOracle.DeployedContracts[] memory deployed = deployScript.runAnyNetwork();

        // Verify deployer is the admin
        LlamaGuardOracle oracle = LlamaGuardOracle(deployed[0].oracle);
        assertTrue(oracle.hasRole(oracle.DEFAULT_ADMIN_ROLE(), deployer), "Deployer should be admin");

        LlamaGuardOracleProxy proxy = LlamaGuardOracleProxy(deployed[0].proxy);
        assertEq(proxy.owner(), deployer, "Deployer should be proxy owner");
    }

    function test_Proxy_OwnershipTransfer_TwoStep() public {
        vm.chainId(31_337);

        DeployLlamaGuardOracle.DeployedContracts[] memory deployed = deployScript.runAnyNetwork();
        LlamaGuardOracleProxy proxy = LlamaGuardOracleProxy(deployed[0].proxy);

        // Transfer ownership
        vm.prank(deployer);
        proxy.transferOwnership(pendingOwner);

        // Owner should still be deployer
        assertEq(proxy.owner(), deployer, "Owner should still be deployer");
        assertEq(proxy.pendingOwner(), pendingOwner, "Pending owner should be set");

        // Accept ownership
        vm.prank(pendingOwner);
        proxy.acceptOwnership();

        assertEq(proxy.owner(), pendingOwner, "Owner should be transferred");
        assertEq(proxy.pendingOwner(), address(0), "Pending owner should be cleared");
    }

    function test_Oracle_AdminRole_Transfer() public {
        vm.chainId(31_337);

        DeployLlamaGuardOracle.DeployedContracts[] memory deployed = deployScript.runAnyNetwork();
        LlamaGuardOracle oracle = LlamaGuardOracle(deployed[0].oracle);

        bytes32 adminRole = oracle.DEFAULT_ADMIN_ROLE();

        // Grant admin role to pending owner
        vm.prank(deployer);
        oracle.grantRole(adminRole, pendingOwner);

        assertTrue(oracle.hasRole(adminRole, pendingOwner), "Pending owner should have admin role");
        assertTrue(oracle.hasRole(adminRole, deployer), "Deployer should still have admin role");

        // Deployer renounces admin role
        vm.prank(deployer);
        oracle.renounceRole(adminRole, deployer);

        assertFalse(oracle.hasRole(adminRole, deployer), "Deployer should no longer have admin role");
        assertTrue(oracle.hasRole(adminRole, pendingOwner), "Pending owner should be sole admin");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ACCESS CONTROL TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Oracle_OnlyAdminCanGrantWriterRole() public {
        vm.chainId(31_337);

        DeployLlamaGuardOracle.DeployedContracts[] memory deployed = deployScript.runAnyNetwork();
        LlamaGuardOracle oracle = LlamaGuardOracle(deployed[0].oracle);

        bytes32 writerRole = oracle.WRITER_ROLE();

        // Unauthorized user cannot grant WRITER_ROLE
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        oracle.grantRole(writerRole, unauthorizedUser);
    }

    function test_Oracle_OnlyAdminCanAddUpdateType() public {
        vm.chainId(31_337);

        DeployLlamaGuardOracle.DeployedContracts[] memory deployed = deployScript.runAnyNetwork();
        LlamaGuardOracle oracle = LlamaGuardOracle(deployed[0].oracle);

        // Unauthorized user cannot add update type
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        oracle.addUpdateType("newType", type(uint256).max);

        // Admin can add update type
        vm.prank(deployer);
        oracle.addUpdateType("newType", type(uint256).max);

        assertTrue(oracle.isValidUpdateType("newType"), "New type should be valid");
    }

    function test_Oracle_OnlyAdminCanAddAuthorizedMarket() public {
        vm.chainId(31_337);

        DeployLlamaGuardOracle.DeployedContracts[] memory deployed = deployScript.runAnyNetwork();
        LlamaGuardOracle oracle = LlamaGuardOracle(deployed[0].oracle);

        address market = makeAddr("market");

        // Unauthorized user cannot add market
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        oracle.addAuthorizedMarket(market);

        // Admin can add market
        vm.prank(deployer);
        oracle.addAuthorizedMarket(market);

        assertTrue(oracle.isAuthorizedMarket(market), "Market should be authorized");
    }

    function test_Proxy_OnlyOwnerCanSetOracle() public {
        vm.chainId(31_337);

        DeployLlamaGuardOracle.DeployedContracts[] memory deployed = deployScript.runAnyNetwork();
        LlamaGuardOracleProxy proxy = LlamaGuardOracleProxy(deployed[0].proxy);

        // Deploy a new oracle to set
        string[] memory updateTypes = new string[](1);
        updateTypes[0] = "test";
        address[] memory markets = new address[](0);

        vm.startPrank(deployer);
        LlamaGuardOracle newOracle = new LlamaGuardOracle(8, "New Oracle", 1, updateTypes, markets);

        // Grant writer access to proxy on new oracle
        newOracle.grantRole(newOracle.WRITER_ROLE(), address(proxy));
        vm.stopPrank();

        // Unauthorized user cannot set oracle
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        proxy.setLlamaGuardOracle(address(newOracle));

        // Owner can set oracle
        vm.prank(deployer);
        proxy.setLlamaGuardOracle(address(newOracle));

        assertEq(address(proxy.llamaguardOracle()), address(newOracle), "Oracle should be updated");
    }

    function test_Proxy_SetOracle_RequiresWriteAccess() public {
        vm.chainId(31_337);

        DeployLlamaGuardOracle.DeployedContracts[] memory deployed = deployScript.runAnyNetwork();
        LlamaGuardOracleProxy proxy = LlamaGuardOracleProxy(deployed[0].proxy);

        // Deploy a new oracle WITHOUT granting write access to proxy
        string[] memory updateTypes = new string[](1);
        updateTypes[0] = "test";
        address[] memory markets = new address[](0);

        vm.startPrank(deployer);
        LlamaGuardOracle newOracle = new LlamaGuardOracle(8, "New Oracle", 1, updateTypes, markets);

        // Setting oracle should fail because proxy doesn't have write access
        vm.expectRevert(LlamaGuardOracleProxy.InvalidLlamaGuardOracle.selector);
        proxy.setLlamaGuardOracle(address(newOracle));
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UPDATE TYPE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Oracle_UpdateTypes_Configured() public {
        vm.chainId(31_337);

        DeployLlamaGuardOracle.DeployedContracts[] memory deployed = deployScript.runAnyNetwork();
        LlamaGuardOracle oracle = LlamaGuardOracle(deployed[0].oracle);

        // Verify configured update types
        assertTrue(oracle.isValidUpdateType("boundedNAV"), "boundedNAV should be valid");
        assertFalse(oracle.isValidUpdateType("invalid"), "invalid should not be valid");
    }

    function test_Oracle_UpdateTypes_Array() public {
        vm.chainId(31_337);

        DeployLlamaGuardOracle.DeployedContracts[] memory deployed = deployScript.runAnyNetwork();
        LlamaGuardOracle oracle = LlamaGuardOracle(deployed[0].oracle);

        // Access public updateTypes array
        // Note: Duplicate update types are deduplicated by LlamaGuardOracle constructor
        string memory type0 = oracle.updateTypes(0);

        assertEq(type0, "boundedNAV", "First update type should be boundedNAV");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SEPOLIA DEPLOYMENT TEST
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Deployment_Sepolia() public {
        vm.chainId(11_155_111);

        DeployLlamaGuardOracle.DeployedContracts[] memory deployed = deployScript.runAnyNetwork();

        assertEq(deployed.length, 2, "Should deploy 2 oracle+proxy pairs on Sepolia");
        assertEq(deployed[0].name, "USCC", "First Sepolia config should be USCC");
        assertEq(deployed[1].name, "USTB", "Second Sepolia config should be USTB");

        LlamaGuardOracle oracle0 = LlamaGuardOracle(deployed[0].oracle);
        assertEq(oracle0.description(), "LlamaGuard USCC Risk Oracle (Sepolia)");

        LlamaGuardOracleProxy proxy0 = LlamaGuardOracleProxy(deployed[0].proxy);
        assertEq(proxy0.description(), "LlamaGuard USCC Oracle Proxy (Sepolia)");

        LlamaGuardOracle oracle1 = LlamaGuardOracle(deployed[1].oracle);
        assertEq(oracle1.description(), "LlamaGuard USTB Risk Oracle (Sepolia)");

        LlamaGuardOracleProxy proxy1 = LlamaGuardOracleProxy(deployed[1].proxy);
        assertEq(proxy1.description(), "LlamaGuard USTB Oracle Proxy (Sepolia)");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // WORKFLOW CONFIG TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Proxy_SetWorkflowConfig() public {
        vm.chainId(31_337);

        DeployLlamaGuardOracle.DeployedContracts[] memory deployed = deployScript.runAnyNetwork();
        LlamaGuardOracleProxy proxy = LlamaGuardOracleProxy(deployed[0].proxy);

        bytes32 newWorkflowId = keccak256("new-workflow");
        address newForwarder = makeAddr("newForwarder");
        address newAuthor = makeAddr("newAuthor");
        bytes10 newWorkflowName = bytes10("newwork001");

        vm.prank(deployer);
        proxy.setWorkflowConfig(newWorkflowId, newForwarder, newAuthor, newWorkflowName, true);

        // Workflow config is set - verification would require accessing internal mapping
        // which is tested via the receive flow in other tests
    }

    function test_Proxy_SetWorkflowActive() public {
        vm.chainId(31_337);

        DeployLlamaGuardOracle.DeployedContracts[] memory deployed = deployScript.runAnyNetwork();
        LlamaGuardOracleProxy proxy = LlamaGuardOracleProxy(deployed[0].proxy);

        // Get the workflow ID from config
        LlamaGuardOracleConfig.DeploymentConfig memory cfg = config.getConfigByIndex(31_337, 0);

        vm.prank(deployer);
        proxy.setWorkflowActive(cfg.proxy.workflowId, false);

        // Workflow should be deactivated
    }

    function test_Proxy_OnlyOwnerCanSetWorkflowConfig() public {
        vm.chainId(31_337);

        DeployLlamaGuardOracle.DeployedContracts[] memory deployed = deployScript.runAnyNetwork();
        LlamaGuardOracleProxy proxy = LlamaGuardOracleProxy(deployed[0].proxy);

        vm.prank(unauthorizedUser);
        vm.expectRevert();
        proxy.setWorkflowConfig(bytes32(0), address(0), address(0), bytes10(0), true);
    }
}
