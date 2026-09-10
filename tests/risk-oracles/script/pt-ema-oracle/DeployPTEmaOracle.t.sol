// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";
import { DeployPTEmaOracle } from "../../../../script/risk-oracles/pt-ema-oracle/DeployPTEmaOracle.s.sol";
import { PTEmaDeployer } from "../../../../script/risk-oracles/pt-ema-oracle/PTEmaDeployer.sol";
import { LlamaGuardOracle } from "llamaguard-contracts/src/LlamaGuardOracle.sol";
import { LlamaGuardOracleProxy } from "llamaguard-contracts/src/LlamaGuardOracleProxy.sol";
import { Addresses } from "../../../../script/risk-oracles/config/Addresses.sol";
import { PTEmaConfig } from "../../../../script/risk-oracles/config/PTEmaConfig.sol";

/// @notice Exercises the `DeployPTEmaOracle` script as a unit test (no fork).
///         Sepolia covers the happy path (config synthesizes non-zero CRE
///         workflow params from the deployer). Plasma covers the deploy-time
///         guard: the workflow params in `Addresses.sol` are placeholders, so
///         a Plasma broadcast must revert with `MissingWorkflowParam` until
///         the multisig fills them in.
contract DeployPTEmaOracleTest is Test {
    function setUp() public {
        // Force-clear `ETH_FROM` so `BaseScript` falls back to the forge test
        // mnemonic — keeps the broadcaster deterministic across chain dispatches.
        vm.setEnv("ETH_FROM", "");
    }

    // ════════════════════════════════════════════════════════════════════════
    // Plasma — guard fires while workflow params are placeholders
    // ════════════════════════════════════════════════════════════════════════

    /// @dev Until `Addresses.PLASMA_STAGING_PT_EMA_WORKFLOW_FORWARDER` (and friends)
    ///      are filled in with real CRE values, a Plasma broadcast must
    ///      revert. This pins that contract on the deploy script.
    function test_deployOnPlasma_revertsWhileWorkflowParamsArePlaceholders() public {
        vm.chainId(Addresses.PLASMA);

        DeployPTEmaOracle script = new DeployPTEmaOracle();
        vm.expectRevert(abi.encodeWithSelector(PTEmaDeployer.MissingWorkflowParam.selector, "emaWorkflowForwarder"));
        script.run();
    }

    // ════════════════════════════════════════════════════════════════════════
    // Sepolia — happy path
    // ════════════════════════════════════════════════════════════════════════

    function test_deployOnSepolia_wiresOraclePipeline() public {
        vm.chainId(Addresses.SEPOLIA);

        DeployPTEmaOracle.Deployed memory deployed = new DeployPTEmaOracle().run();

        // For Sepolia the config is deployer-derived. Re-derive the
        // broadcaster the same way `BaseScript` does so the config comparison
        // lines up.
        address broadcaster = _deriveBroadcaster();
        PTEmaConfig.PTEmaDeployConfig memory cfg = PTEmaConfig.getSepoliaConfig(broadcaster);
        _assertDeployment(deployed, cfg);
    }

    // ════════════════════════════════════════════════════════════════════════
    // Unsupported chain
    // ════════════════════════════════════════════════════════════════════════

    function test_deployOnUnsupportedChain_reverts() public {
        vm.chainId(424_242);
        DeployPTEmaOracle script = new DeployPTEmaOracle();
        vm.expectRevert(abi.encodeWithSelector(DeployPTEmaOracle.UnsupportedChain.selector, uint256(424_242)));
        script.run();
    }

    // ════════════════════════════════════════════════════════════════════════
    // Helpers
    // ════════════════════════════════════════════════════════════════════════

    function _assertDeployment(
        DeployPTEmaOracle.Deployed memory deployed,
        PTEmaConfig.PTEmaDeployConfig memory cfg
    )
        internal
        view
    {
        assertTrue(deployed.oracle != address(0), "oracle not deployed");
        assertTrue(deployed.oracleProxy != address(0), "oracle proxy not deployed");

        LlamaGuardOracle oracle = LlamaGuardOracle(deployed.oracle);
        LlamaGuardOracleProxy proxy = LlamaGuardOracleProxy(deployed.oracleProxy);

        // Oracle metadata + initial state.
        assertEq(oracle.decimals(), cfg.oracleDecimals, "decimals");
        assertEq(oracle.version(), cfg.oracleVersion, "version");
        assertEq(oracle.description(), cfg.oracleDescription, "description");
        assertTrue(oracle.isValidUpdateType(PTEmaConfig.UPDATE_TYPE_EMA), "EMA update type not registered");

        // Authorized markets — at least the first market in cfg must be live.
        for (uint256 i = 0; i < cfg.initialAuthorizedMarkets.length; i++) {
            assertTrue(oracle.isAuthorizedMarket(cfg.initialAuthorizedMarkets[i]), "configured market not authorized");
        }

        // Writer role wiring (broadcaster == owner in both supported chains
        // here, so the script grants WRITER_ROLE inline).
        assertTrue(oracle.hasWriteAccess(address(proxy)), "proxy missing WRITER_ROLE");

        // Proxy → oracle pointer.
        assertEq(address(proxy.llamaguardOracle()), deployed.oracle, "proxy.llamaguardOracle mismatch");

        // CRE workflow config: the constructor seeds workflowConfigs[workflowId] with isActive=true.
        (address expectedForwarder, address expectedAuthor, bytes10 expectedWorkflowName, bool isActive) =
            proxy.workflowConfigs(cfg.emaWorkflowId);
        assertEq(expectedForwarder, cfg.emaWorkflowForwarder, "workflow forwarder mismatch");
        assertEq(expectedAuthor, cfg.emaWorkflowAuthor, "workflow author mismatch");
        assertEq(expectedWorkflowName, cfg.emaWorkflowName, "workflow name mismatch");
        assertTrue(isActive, "workflow not active");
    }

    function _deriveBroadcaster() internal returns (address broadcaster) {
        string memory mnemonic = "test test test test test test test test test test test junk";
        (broadcaster,) = deriveRememberKey(mnemonic, 0);
    }
}
