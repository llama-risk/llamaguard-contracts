// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";
import { CapsBorrowForwarder } from "../../src/caps-oracle/CapsBorrowForwarder.sol";
import { CapsConfig } from "../../script/risk-oracles/caps/CapsConfig.sol";
import { CapsDeployment } from "../../script/risk-oracles/caps/CapsDeployment.sol";
import { DeployForwarder } from "../../script/risk-oracles/caps/5_DeployForwarder.s.sol";

/// @notice Step 5 against the production deployment on an Arbitrum fork, with example limits in place of the TODOs.
contract CapsProductionForwarderForkTest is Test {
    string internal constant LABEL = "arbitrum-core-production";
    address internal constant EXECUTOR = 0xFF1137243698CaA18EE364Cc966CF0e02A4e6327;
    address internal constant RISK_COUNCIL = 0x3Be327F22eB4BD8042e6944073b8826dCf357Aa2;

    bool internal forked;

    function setUp() public {
        string memory rpc = vm.envOr("ARBITRUM_RPC_URL", string(""));
        if (bytes(rpc).length == 0 || keccak256(bytes(vm.envOr("FOUNDRY_PROFILE", string("")))) != keccak256("fork")) {
            return;
        }
        vm.createSelectFork(rpc);
        forked = true;
    }

    function test_deployForwarder_onTheProductionStack() public {
        vm.skip(!forked);
        CapsConfig.Config memory config;
        config.market = CapsConfig.loadMarket(LABEL);
        CapsDeployment.Deployment memory d = CapsDeployment.read(LABEL);
        CapsConfig.Forwarder memory f = CapsConfig.Forwarder({
            owner: EXECUTOR, caller: RISK_COUNCIL, maxRaiseBuffers: 3, minRaiseDelay: 30 minutes
        });

        d = new DeployForwarder().deployForwarder(config, f, d, makeAddr("deployer"));

        CapsBorrowForwarder fwd = CapsBorrowForwarder(d.forwarder);
        assertEq(fwd.owner(), EXECUTOR);
        assertTrue(fwd.isCaller(RISK_COUNCIL));
        assertEq(fwd.POOL(), config.market.pool);
        assertEq(fwd.CONFIG_ENGINE(), config.market.configEngine);
        assertEq(fwd.RVM(), d.rvm);
        assertEq(fwd.maxRaiseBuffers(), 3);
        assertEq(fwd.minRaiseDelay(), 30 minutes);
    }
}
