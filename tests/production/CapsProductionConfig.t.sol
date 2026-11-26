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

    /// @dev The fresh production EOA. It only holds the RiskOracle and the Router until the hand-over.
    function test_production_deployer() public view {
        assertEq(CapsConfig.load(LABEL).roles.deployer, 0x95e6dEEb6863Adb187969De2f8B163E6536B52BA);
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
        assertEq(m.assets, "arbitrum-core-production");
    }

    function test_production_route() public view {
        CapsConfig.Route memory route = CapsConfig.loadRoute(LABEL);
        assertEq(route.forwarder, 0xF8344CFd5c43616a4366C34E3EEE75af79a74482, "Arbitrum KeystoneForwarder");
        assertEq(route.workflowOwner, 0x73494691C9B28b91A0b4C9dF213c1893fddA3a3B, "Aave CRE workflow owner");
        assertEq(route.maxReportAgeSeconds, 360);
    }

    function test_production_roles() public view {
        CapsConfig.Roles memory r = CapsConfig.load(LABEL).roles;
        assertEq(r.agentHubOwner, EXECUTOR);
        assertEq(r.rvmOwner, EXECUTOR);
        assertEq(r.registryOwner, EXECUTOR);
        assertEq(r.agentAdmin, PROTOCOL_GUARDIAN);
        assertEq(r.routerGuardian, PROTOCOL_GUARDIAN);
        assertEq(r.riskOracleOwner, ADMIN_SAFE);
        assertEq(r.routerOwner, ADMIN_SAFE);
        assertEq(r.routerUpdater, ADMIN_SAFE);
        assertEq(r.registryUpdater, ADMIN_SAFE);
        assertEq(r.riskCouncil, RISK_COUNCIL);
    }

    /// @dev Every reserve of the Pool except GHO, so one re-enabled later is already rate limited.
    function test_production_assets() public view {
        CapsConfig.Assets memory a = CapsConfig.loadAssets(CapsConfig.loadMarket(LABEL).assets);
        assertEq(a.reserves.length, 19);
        assertEq(a.skip.length, 1);
        assertEq(a.skip[0], 0x7dfF72693f6A4149b17e7C6314655f6A9F7c8B33, "GHO stays out of the rate limiter");
        for (uint256 i; i < a.reserves.length; ++i) {
            assertGt(a.reserves[i].maxHeadroom, 0, a.reserves[i].symbol);
            assertEq(a.reserves[i].alphaBps, 1000, "alpha 10%");
            assertEq(a.reserves[i].cutBandBps, 1000, "delta 10%");
            if (a.reserves[i].asset == 0xba5DdD1f9d7F570dc94a51479a000E3BCE967196) {
                assertFalse(a.reserves[i].currentCap, "AAVE has no cap, so its hard maximum is set");
                assertEq(a.reserves[i].maxCap, 1);
            } else {
                assertTrue(a.reserves[i].currentCap, a.reserves[i].symbol);
            }
        }
        assertEq(a.reserves[4].symbol, "wstETH");
        assertEq(a.reserves[4].maxHeadroom, 6625, "$15M of wstETH");
    }

    /// @dev Step 5 cannot run until the risk team sets both limits.
    function test_production_forwarderLimitsAreTodo() public {
        vm.expectRevert(bytes("CapsConfig: .forwarder.maxRaiseBuffers is TODO"));
        this.loadForwarder();
        string memory json = vm.readFile("script/risk-oracles/caps/config/arbitrum-core-production.json");
        assertEq(vm.parseJsonAddress(json, ".forwarder.owner"), EXECUTOR, "same owner as the AgentHub");
        assertEq(vm.parseJsonAddress(json, ".forwarder.caller"), RISK_COUNCIL);
    }

    function loadForwarder() external view returns (CapsConfig.Forwarder memory) {
        return CapsConfig.loadForwarder(LABEL);
    }
}
