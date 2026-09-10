// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { EthereumCoreForkTest } from "./EthereumCoreForkTest.sol";
import { LlamaguardRiskOracleRouter } from "../../../../src/LlamaguardRiskOracleRouter.sol";
import { PTParameterRegistry } from "../../../../src/PTParameterRegistry.sol";
import { ActivateEthereumCore } from "../../../../script/risk-oracles/ethereum/production/1_ActivateEthereumCore.s.sol";
import {
    ActivatePTsrUSDe22OCT2026
} from "../../../../script/risk-oracles/ethereum/production/2_ActivatePTsrUSDe22OCT2026.s.sol";
import { EthereumCoreConfig } from "../../../../script/risk-oracles/ethereum/production/EthereumCoreConfig.sol";
import { PTsrUSDe22OCT2026 } from "../../../../script/risk-oracles/ethereum/production/assets/PTsrUSDe22OCT2026.sol";

/// @notice Everything a fork exercise of the per-asset stack needs, up to and including phase 2.
/// @dev    Split out from the phase 2 suite so the phase 3 suite can reach the same live stack
///         without re-running phase 2's assertions. `_throughPhase2` is the whole of it: phase 1,
///         the safe accepting the Router, phase 2, and the registry write the safe makes.
///
///         Skips unless `MAINNET_RPC_URL` is set and the `fork` profile is active:
///
///           FOUNDRY_PROFILE=fork forge test --match-path "tests/script/ethereum-production/*"
abstract contract EthereumCoreAssetForkBase is EthereumCoreForkTest {
    ActivateEthereumCore internal step1;
    ActivatePTsrUSDe22OCT2026 internal step2;

    struct Stack {
        address riskOracle;
        address registry;
        address router;
        address emaOracle;
        address discountAgent;
        address emodeAgent;
        uint256 discountAgentId;
        uint256 emodeAgentId;
    }

    function _setUpThroughPhase2() internal {
        _setUpFork();
        if (!forked) return;

        step1 = new ActivateEthereumCore();
        step2 = new ActivatePTsrUSDe22OCT2026();
    }

    function _throughPhase2() internal returns (Stack memory stack) {
        EthereumCoreConfig.Acl memory acl = EthereumCoreConfig.acl();

        ActivateEthereumCore.Deployment memory core = step1.deploy(address(step1), acl);
        stack.riskOracle = core.riskOracle;
        stack.registry = core.ptParameterRegistry;
        stack.router = core.router;

        // Phase 1 ends with the safe accepting the Router.
        vm.prank(acl.routerOwner);
        LlamaguardRiskOracleRouter(stack.router).acceptOwnership();

        stack.emaOracle = step2.deploy(address(step2), stack.router, acl).emaOracle;

        vm.prank(acl.registryUpdater);
        PTParameterRegistry(stack.registry)
            .setPtMarketParams(PTsrUSDe22OCT2026.PT_ASSET, PTsrUSDe22OCT2026.ptMarketParams());
    }
}
