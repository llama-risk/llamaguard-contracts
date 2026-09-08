// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { EthereumCoreAssetForkBase } from "./EthereumCoreAssetForkBase.sol";
import { ILlamaGuardOracle } from "llamaguard-contracts/src/interfaces/ILlamaGuardOracle.sol";
import { LlamaGuardOracle } from "llamaguard-contracts/src/LlamaGuardOracle.sol";
import { PTParameterRegistry } from "../../../../src/PTParameterRegistry.sol";
import { EthereumCoreConfig } from "../../../../script/risk-oracles/ethereum/production/EthereumCoreConfig.sol";
import { PTsrUSDe22OCT2026 } from "../../../../script/risk-oracles/ethereum/production/assets/PTsrUSDe22OCT2026.sol";

/// @notice Fork exercise of phase 2, the per-asset activation, against live Ethereum mainnet.
/// @dev    Skips unless `MAINNET_RPC_URL` is set and the `fork` profile is active:
///
///           FOUNDRY_PROFILE=fork forge test --match-path "tests/script/ethereum-production/*"
contract EthereumCoreAssetForkTest is EthereumCoreAssetForkBase {
    function setUp() public {
        _setUpThroughPhase2();
    }

    function test_phase2LeavesTheEmaOracleWritableOnlyByTheRouter() public {
        _skipUnlessForked();

        Stack memory stack = _throughPhase2();

        assertTrue(
            ILlamaGuardOracle(stack.emaOracle).hasWriteAccess(stack.router),
            "Router lacks WRITER_ROLE on the EMA oracle"
        );
        assertFalse(
            LlamaGuardOracle(stack.emaOracle).hasRole(0x00, address(step2)), "deployer still holds DEFAULT_ADMIN_ROLE"
        );
        assertTrue(
            LlamaGuardOracle(stack.emaOracle).hasRole(0x00, EthereumCoreConfig.LLAMARISK_SAFE), "safe is not the admin"
        );
    }

    /// @dev Pins the state of the EMA leg's bounding rather than leaving it implicit. The oracle
    ///      ships with its deviation guard off, and the Router adds nothing on top of it, so the
    ///      first person to ask "what stops a bad EMA" has an assertion to read. Change this test
    ///      when a deviation is chosen, not before.
    function test_theEmaOracleShipsWithItsDeviationGuardOff() public {
        _skipUnlessForked();

        Stack memory stack = _throughPhase2();
        assertEq(LlamaGuardOracle(stack.emaOracle).maxPriceDeviation(), 0, "a deviation was set without a decision");
    }

    function test_theRegistryWriteLandsForThisReserve() public {
        _skipUnlessForked();

        Stack memory stack = _throughPhase2();

        PTParameterRegistry.PtMarketParams memory params =
            PTParameterRegistry(stack.registry).getPtMarketParams(PTsrUSDe22OCT2026.PT_ASSET);
        assertTrue(params.enabled, "PT market not enabled in the registry");
        assertEq(params.emaSpan, PTsrUSDe22OCT2026.EMA_SPAN, "ema span");
        assertEq(params.emodeCategoryIds.length, 2, "expected two eMode ids");
        assertEq(params.emodeCategoryIds[0], PTsrUSDe22OCT2026.EMODE_STABLECOINS);
        assertEq(params.emodeCategoryIds[1], PTsrUSDe22OCT2026.EMODE_USDE);
    }

    // ============================================================================================
    // Phase 3, the routes
    // ============================================================================================
}
