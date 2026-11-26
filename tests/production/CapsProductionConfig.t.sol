// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";
import { CapsConfig } from "../../script/risk-oracles/caps/CapsConfig.sol";

/// @notice The production config parses to the roles and values the deployment and the AIP expect.
contract CapsProductionConfigTest is Test {
    string internal constant LABEL = "arbitrum-core-production";

    address internal constant EXECUTOR = 0xFF1137243698CaA18EE364Cc966CF0e02A4e6327; // GovernanceV3Arbitrum lvl 1
    address internal constant PROTOCOL_GUARDIAN = 0xCb45E82419baeBCC9bA8b1e5c7858e48A3B26Ea6; // MiscArbitrum
    address internal constant ADMIN_SAFE = 0x1a0267E9E5929a5914Ae9DbBf23Bc07B14365471; // LLAMARISK_RISK_ORACLE_ADMIN_SAFE
    address internal constant RISK_COUNCIL = 0x3Be327F22eB4BD8042e6944073b8826dCf357Aa2;

    /// @dev Nothing deploys until the prod EOA is filled in.
    function test_production_deployerIsTodo() public {
        vm.expectRevert(bytes("CapsConfig: .roles.deployer is TODO"));
        this.loadRoles();
    }

    function test_production_market() public view {
        CapsConfig.Market memory m = CapsConfig.loadMarket(LABEL);
        assertEq(m.chainId, 42_161);
        assertFalse(m.shadow, "the real Pool");
        assertEq(m.pool, 0x794a61358D6845594F94dc1DB02A252b5b4814aD, "Aave V3 Arbitrum Pool");
        assertEq(m.agentHub, 0xf4F2bc657abe96863dC1Ae17C9e9fFfc2B420e7B, "MiscArbitrum.AGENT_HUB");
        assertEq(m.configEngine, 0xFaEe011b679330A42fFc33c6444800F78b69Dc58, "AaveV3Arbitrum.CONFIG_ENGINE");
        assertEq(CapsConfig.borrowUpdateType(m), "BorrowCapUpdate_Core");
        assertEq(m.expirationSeconds, 60, "pending raises expire after one minute");
        assertEq(m.tauSeconds, 1800, "tau 30 min");
        assertEq(m.bounds.alphaBpsLimit, 2000);
        assertEq(m.bounds.cutBandBpsLimit, 2000);
        assertEq(m.bounds.maxIncreaseBps, 5000);
        assertEq(m.bounds.cooldown, 1 days);
        assertEq(m.defaults.triggerBps, 2000, "theta 20%, as in the ARFC");
        assertEq(m.defaults.marginBps, 100);
        assertEq(m.defaults.minMarginTokens, 1);
        assertEq(m.assets, "arbitrum-core", "same asset values as staging");
    }

    function test_production_route() public view {
        CapsConfig.Route memory route = CapsConfig.loadRoute(LABEL);
        assertEq(route.forwarder, 0xF8344CFd5c43616a4366C34E3EEE75af79a74482, "Arbitrum KeystoneForwarder");
        assertEq(route.workflowOwner, 0x73494691C9B28b91A0b4C9dF213c1893fddA3a3B, "Aave CRE workflow owner");
        assertEq(route.maxReportAgeSeconds, 360);
    }

    /// @dev Read key by key: `CapsConfig.load` stops on the TODO deployer.
    function test_production_roles() public view {
        string memory json = vm.readFile("script/risk-oracles/caps/config/arbitrum-core-production.json");
        assertEq(vm.parseJsonAddress(json, ".roles.agentHubOwner"), EXECUTOR);
        assertEq(vm.parseJsonAddress(json, ".roles.rvmOwner"), EXECUTOR);
        assertEq(vm.parseJsonAddress(json, ".roles.registryOwner"), EXECUTOR);
        assertEq(vm.parseJsonAddress(json, ".roles.agentAdmin"), PROTOCOL_GUARDIAN);
        assertEq(vm.parseJsonAddress(json, ".roles.routerGuardian"), PROTOCOL_GUARDIAN);
        assertEq(vm.parseJsonAddress(json, ".roles.riskOracleOwner"), ADMIN_SAFE);
        assertEq(vm.parseJsonAddress(json, ".roles.routerOwner"), ADMIN_SAFE);
        assertEq(vm.parseJsonAddress(json, ".roles.routerUpdater"), ADMIN_SAFE);
        assertEq(vm.parseJsonAddress(json, ".roles.registryUpdater"), ADMIN_SAFE);
        assertEq(vm.parseJsonAddress(json, ".roles.riskCouncil"), RISK_COUNCIL);
    }

    function loadRoles() external view returns (CapsConfig.Roles memory) {
        return CapsConfig.load(LABEL).roles;
    }
}
