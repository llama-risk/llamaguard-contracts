// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";
import { WireEmaRoute } from "../../../../script/risk-oracles/ethereum/production/3a_WireEmaRoute.s.sol";
import { PTsrUSDe22OCT2026 } from "../../../../script/risk-oracles/ethereum/production/assets/PTsrUSDe22OCT2026.sol";

/// @notice The `bytes10` route name phase 3 derives from a workflow name.
/// @dev    Needs no fork, so it must not live in a suite that skips without an RPC. `addRoute`
///         accepts any wrong name and only rejects `bytes10(0)`, there is no setter to correct one,
///         and the mistake surfaces only when the first live report is rejected.
contract EthereumCoreWorkflowNameTest is Test {
    /// @dev The first group are name/value pairs an earlier Router already holds onchain, which is
    ///      what makes this an assertion about CRE rather than about our own implementation. A
    ///      derived value bears no resemblance to the name it came from, which is why they are here:
    ///      a test that feeds the same raw name into both sides passes while proving nothing.
    function test_creWorkflowNameDerivation() public {
        WireEmaRoute derive = new WireEmaRoute();

        assertEq(derive.creWorkflowName("pt-ema-plasma-susde-22oct26-staging"), bytes10("51f5ca3cac"));
        assertEq(derive.creWorkflowName("pt-dro-plasma-susde-22oct26-staging"), bytes10("34fa91c912"));
        assertEq(derive.creWorkflowName("pt-rpo-plasma-susde-22oct26-staging"), bytes10("7a01fa9488"));

        bytes10 ema = derive.creWorkflowName(PTsrUSDe22OCT2026.EMA_WORKFLOW_NAME);
        bytes10 dro = derive.creWorkflowName(PTsrUSDe22OCT2026.DISCOUNT_WORKFLOW_NAME);
        bytes10 rpo = derive.creWorkflowName(PTsrUSDe22OCT2026.RISK_PARAMS_WORKFLOW_NAME);
        assertTrue(ema != dro && dro != rpo && ema != rpo, "production workflow names collide");
        assertTrue(ema != derive.creWorkflowName("pt-ema-eth-srusde-22oct26-staging"), "production reuses staging");

        // The rule has no length threshold, so a name short enough to fit in ten bytes is still
        // hashed. This is the case that makes `cast format-bytes32-string "<name>"` look correct.
        assertTrue(derive.creWorkflowName("pt-ema-eth") != bytes10("pt-ema-eth"));
    }
}
