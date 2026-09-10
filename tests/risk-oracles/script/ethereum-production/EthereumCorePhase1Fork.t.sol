// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { EthereumCoreForkTest } from "./EthereumCoreForkTest.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IRiskOracle } from "aave-v3-risk-stewards/contracts/dependencies/IRiskOracle.sol";
import { RiskOracle } from "aave-v3-risk-stewards/contracts/dependencies/RiskOracle.sol";
import { LlamaguardRiskOracleRouter } from "../../../../src/LlamaguardRiskOracleRouter.sol";
import { PTParameterRegistry } from "../../../../src/PTParameterRegistry.sol";
import { ActivateEthereumCore } from "../../../../script/risk-oracles/ethereum/production/1_ActivateEthereumCore.s.sol";
import { EthereumCoreConfig } from "../../../../script/risk-oracles/ethereum/production/EthereumCoreConfig.sol";
import {
    EthereumCoreExternalAddresses
} from "../../../../script/risk-oracles/ethereum/production/EthereumCoreExternalAddresses.sol";
import { SafeTx } from "../../../../script/risk-oracles/ethereum/production/SafeTx.sol";

/// @notice Fork exercise of phase 1 against live Ethereum mainnet.
/// @dev    Skips unless `MAINNET_RPC_URL` is set and the `fork` profile is active:
///
///           FOUNDRY_PROFILE=fork forge test --match-path "tests/script/ethereum-production/*"
///
///         Phase 1 calls no Aave contract, so a fork buys two things the default profile cannot:
///         the production ACL constants resolve against the real Executor and the real Aave protocol
///         guardian, and the chain id guard in `EthereumCoreConfig.validate` is the live one.
contract EthereumCorePhase1ForkTest is EthereumCoreForkTest {
    ActivateEthereumCore internal step1;

    struct Stack {
        address riskOracle;
        address registry;
        address router;
    }

    function setUp() public {
        _setUpFork();
        if (!forked) return;
        step1 = new ActivateEthereumCore();
    }

    // ============================================================================================
    // What phase 1 leaves behind
    // ============================================================================================

    /// @dev The registry never passes through the deployer. The RiskOracle does and leaves in the
    ///      same transaction. The Router does and stays until the safe accepts, which is the whole
    ///      of what the printed batch is for.
    function test_phase1LeavesTheStackInTheDocumentedState() public {
        _skipUnlessForked();

        Stack memory stack = _activate();

        assertEq(RiskOracle(stack.riskOracle).owner(), EthereumCoreConfig.LLAMARISK_SAFE, "RiskOracle owner");
        assertEq(
            PTParameterRegistry(stack.registry).owner(),
            EthereumCoreExternalAddresses.AAVE_EXECUTOR,
            "registry owner is not the Executor"
        );
        assertEq(PTParameterRegistry(stack.registry).updater(), EthereumCoreConfig.LLAMARISK_SAFE, "registry updater");

        LlamaguardRiskOracleRouter router = LlamaguardRiskOracleRouter(stack.router);
        assertEq(router.updater(), EthereumCoreConfig.LLAMARISK_SAFE, "Router updater");
        assertEq(router.guardian(), EthereumCoreExternalAddresses.AAVE_PROTOCOL_GUARDIAN, "Router guardian");

        // Two step, so the deployer is still owner and the safe is only pending.
        assertEq(router.owner(), address(step1), "Router owner left the deployer early");
        assertEq(router.pendingOwner(), EthereumCoreConfig.LLAMARISK_SAFE, "Router handover not started");
    }

    /// @dev The RiskOracle is constructed with exactly the two types the agents will answer to, and
    ///      no third. `EmaImpliedRateUpdate` being absent is deliberate: that leg writes to the
    ///      LlamaGuardOracle and never touches this contract.
    function test_riskOracleCarriesOnlyTheTwoAgentUpdateTypes() public {
        _skipUnlessForked();

        Stack memory stack = _activate();

        string[] memory types = RiskOracle(stack.riskOracle).getAllUpdateTypes();
        assertEq(types.length, 2, "expected exactly two update types");
        assertEq(types[0], EthereumCoreConfig.TYPE_DISCOUNT, "first update type");
        assertEq(types[1], EthereumCoreConfig.TYPE_EMODE, "second update type");
    }

    /// @dev `_verify` asserts the grant through `isAuthorized`, which covers the positive case.
    ///      This exercises the behaviour behind the flag: that the Router can actually publish and
    ///      that the deployer cannot, which is what proves the grant is the single one intended
    ///      rather than a blanket one.
    function test_onlyTheRouterMayPublish() public {
        _skipUnlessForked();

        Stack memory stack = _activate();

        vm.prank(stack.router);
        IRiskOracle(stack.riskOracle)
            .publishRiskParameterUpdate(
                "phase1-authorisation-probe",
                abi.encode(uint256(1)),
                EthereumCoreConfig.TYPE_DISCOUNT,
                address(0xBEEF),
                ""
            );

        vm.prank(address(step1));
        vm.expectRevert(bytes("Unauthorized: Sender not authorized."));
        IRiskOracle(stack.riskOracle)
            .publishRiskParameterUpdate(
                "phase1-authorisation-probe",
                abi.encode(uint256(1)),
                EthereumCoreConfig.TYPE_DISCOUNT,
                address(0xBEEF),
                ""
            );
    }

    // ============================================================================================
    // The safe batch, and the guardian it hands governance
    // ============================================================================================

    /// @dev Executes the printed batch exactly as the safe will, then asserts the handover completed
    ///      and the deployer holds nothing.
    function test_theSafeBatchCompletesTheHandover() public {
        _skipUnlessForked();

        Stack memory stack = _activate();
        LlamaguardRiskOracleRouter router = LlamaguardRiskOracleRouter(stack.router);

        _executeSafeBatch(stack);

        assertEq(router.owner(), EthereumCoreConfig.LLAMARISK_SAFE, "Router owner after acceptance");
        assertEq(router.pendingOwner(), address(0), "pending owner not cleared");

        // The deploy key is done. It owns nothing and can change nothing.
        vm.prank(address(step1));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(step1)));
        router.setUpdater(address(0xDEAD));
    }

    /// @dev The reason the guardian is Aave's emergency multisig rather than our own safe: it is a
    ///      kill switch governance can pull without a proposal, and cannot use to hold the stack
    ///      down, because `unpause` is owner-only.
    function test_theAaveGuardianCanPauseButNotUnpause() public {
        _skipUnlessForked();

        Stack memory stack = _activate();
        LlamaguardRiskOracleRouter router = LlamaguardRiskOracleRouter(stack.router);
        _executeSafeBatch(stack);

        address guardian = EthereumCoreExternalAddresses.AAVE_PROTOCOL_GUARDIAN;

        vm.prank(guardian);
        router.pause();
        assertTrue(router.paused(), "guardian could not pause");

        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, guardian));
        router.unpause();
        assertTrue(router.paused(), "guardian unpaused a stack it should not be able to restart");

        vm.prank(EthereumCoreConfig.LLAMARISK_SAFE);
        router.unpause();
        assertFalse(router.paused(), "owner could not unpause");
    }

    /// @dev Nobody outside the two slots can stop the stack.
    function test_anArbitraryAccountCannotPause() public {
        _skipUnlessForked();

        Stack memory stack = _activate();
        _executeSafeBatch(stack);

        vm.prank(address(0xA11CE));
        vm.expectRevert(LlamaguardRiskOracleRouter.NotOwnerOrGuardian.selector);
        LlamaguardRiskOracleRouter(stack.router).pause();
    }

    // ============================================================================================
    // Helpers
    // ============================================================================================

    /// @dev Called directly rather than through `run()`. The deployer argument must be the account
    ///      the calls actually originate from, which here is the script contract, so the Router is
    ///      constructed owned by the account that then sets its updater.
    function _activate() internal returns (Stack memory stack) {
        ActivateEthereumCore.Deployment memory core = step1.deploy(address(step1), EthereumCoreConfig.acl());
        stack.riskOracle = core.riskOracle;
        stack.registry = core.ptParameterRegistry;
        stack.router = core.router;
    }

    /// @dev Runs the batch the script prints, from the signer it names, with nothing re-derived.
    function _executeSafeBatch(Stack memory stack) internal {
        SafeTx.Call[] memory calls = step1.safeCalls(stack.router);
        assertEq(calls.length, 1, "expected a single acceptOwnership call");

        for (uint256 i = 0; i < calls.length; i++) {
            vm.prank(EthereumCoreConfig.ROUTER_OWNER);
            (bool ok, bytes memory reason) = calls[i].to.call(calls[i].data);
            if (!ok) {
                assembly {
                    revert(add(reason, 0x20), mload(reason))
                }
            }
        }
    }
}
