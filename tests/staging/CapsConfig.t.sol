// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";
import { CapsConfig } from "../../script/risk-oracles/caps/CapsConfig.sol";

/// @notice The committed staging files parse to the values the deployment expects.
contract CapsConfigTest is Test {
    string internal constant LABEL = "arbitrum-core-staging";
    address internal constant STAGING_EOA = 0xdBb36783D324cb1dabea7ccb61647623aA85BcCC;

    function test_staging_rolesAreTheStagingEoa() public view {
        CapsConfig.Roles memory r = CapsConfig.load(LABEL).roles;
        address[12] memory all = [
            r.deployer,
            r.agentHubOwner,
            r.agentAdmin,
            r.shadowPoolOwner,
            r.riskOracleOwner,
            r.routerOwner,
            r.routerUpdater,
            r.routerGuardian,
            r.registryOwner,
            r.registryUpdater,
            r.rvmOwner,
            r.riskCouncil
        ];
        for (uint256 i; i < all.length; ++i) {
            assertEq(all[i], STAGING_EOA);
        }
    }

    function test_staging_route() public view {
        CapsConfig.Route memory route = CapsConfig.loadRoute(LABEL);
        assertEq(route.forwarder, 0xF8344CFd5c43616a4366C34E3EEE75af79a74482, "Arbitrum KeystoneForwarder");
        assertEq(route.workflowOwner, 0x4EDEaFc9b862F08464423EFe9423153B22B28f17, "llr-multisig, the CRE owner");
        assertEq(route.maxReportAgeSeconds, 360);
    }

    function test_staging_market() public view {
        CapsConfig.Market memory m = CapsConfig.loadMarket(LABEL);
        assertEq(m.chainId, 42_161);
        assertTrue(m.shadow);
        assertEq(m.pool, 0x794a61358D6845594F94dc1DB02A252b5b4814aD, "Aave V3 Arbitrum Pool");
        assertEq(CapsConfig.borrowUpdateType(m), "BorrowCapUpdate_Core");
        assertEq(m.expirationSeconds, 60, "pending raises expire after one minute");
        assertEq(m.tauSeconds, 1800, "tau 30 min");
        assertEq(m.defaults.triggerBps, 2000, "theta 20%");
        assertEq(m.defaults.marginBps, 100);
        assertEq(m.defaults.minMarginTokens, 1);
        assertGt(m.bounds.cooldown, 0, "the RVM rejects a zero cooldown");
    }

    function test_staging_assets() public view {
        CapsConfig.Assets memory a = CapsConfig.loadAssets(CapsConfig.loadMarket(LABEL).assets);
        assertEq(a.reserves.length, 4);
        assertEq(a.skip.length, 16);
        assertEq(a.skip[0], 0x7dfF72693f6A4149b17e7C6314655f6A9F7c8B33, "GHO stays out of the rate limiter");
        for (uint256 i; i < a.reserves.length; ++i) {
            assertTrue(a.reserves[i].currentCap, a.reserves[i].symbol);
            assertGt(a.reserves[i].maxHeadroom, 0, a.reserves[i].symbol);
            assertEq(a.reserves[i].alphaBps, 1000, "alpha 10%");
            assertEq(a.reserves[i].cutBandBps, 1000, "delta 10%");
        }
        assertEq(a.reserves[1].symbol, "WETH");
        assertEq(a.reserves[1].maxHeadroom, 8282, "$15M of WETH");
    }
}
