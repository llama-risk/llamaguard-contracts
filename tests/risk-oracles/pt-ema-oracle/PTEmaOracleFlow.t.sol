// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";
import { LlamaGuardOracle } from "llamaguard-contracts/src/LlamaGuardOracle.sol";
import { LlamaGuardOracleProxy } from "llamaguard-contracts/src/LlamaGuardOracleProxy.sol";
import { ILlamaGuardOracle } from "llamaguard-contracts/src/interfaces/ILlamaGuardOracle.sol";
import { AbstractCreReceiver } from "llamaguard-contracts/src/abstracts/AbstractCreReceiver.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @notice End-to-end happy-path + revert-path coverage for the PT EMA oracle
///         pipeline. Mirrors the on-chain wiring the deploy script produces:
///         CRE forwarder → LlamaGuardOracleProxy → LlamaGuardOracle, with
///         downstream reads going directly through `LlamaGuardOracle`.
contract PTEmaOracleFlowTest is Test {
    LlamaGuardOracle internal oracle;
    LlamaGuardOracleProxy internal receiverProxy;

    address internal forwarder = makeAddr("cre-forwarder");
    address internal author = makeAddr("cre-author");
    address internal ptMarket = makeAddr("plasma-pt-market");
    bytes32 internal workflowId = bytes32(uint256(0xE3A));
    bytes10 internal workflowName = bytes10("ema_v1____");

    string internal constant UPDATE_TYPE_EMA = "EmaImpliedRateUpdate";

    function setUp() public {
        string[] memory updateTypes = new string[](1);
        updateTypes[0] = UPDATE_TYPE_EMA;

        address[] memory markets = new address[](1);
        markets[0] = ptMarket;

        oracle = new LlamaGuardOracle(18, "PT EMA Implied Rate (test)", 1, updateTypes, markets);

        receiverProxy = new LlamaGuardOracleProxy(
            address(oracle), workflowId, forwarder, author, workflowName, "PT EMA receiver (test)"
        );

        oracle.grantRole(oracle.WRITER_ROLE(), address(receiverProxy));
    }

    // ════════════════════════════════════════════════════════════════════════
    // HAPPY PATH
    // ════════════════════════════════════════════════════════════════════════

    /// @dev Drives the full pipeline: a CRE report lands at the receiver
    ///      proxy, gets decoded, calls `updateLatestRiskRoundData` on the
    ///      oracle, and the new EMA value becomes readable through the direct
    ///      oracle interface.
    function test_onReportPropagatesEmaToOracle() public {
        int256 emaRaw = 5_237_182_400_000_000; // ~0.5237% raw EMA, 1e18 scale
        bytes memory additionalData = _encodeEmaAdditionalData(emaRaw, block.timestamp);
        bytes memory report = _encodeUpdateInput("ema-round-1", emaRaw, additionalData, block.timestamp + 1 hours);
        bytes memory metadata = _buildMetadata(workflowId, workflowName, author);

        vm.prank(forwarder);
        LlamaGuardOracleProxy(receiverProxy).onReport(metadata, report);

        (uint80 roundIdDirect, int256 answerDirect,,,) = oracle.latestRoundData();
        assertEq(answerDirect, emaRaw, "oracle.latestRoundData answer mismatch");
        assertEq(roundIdDirect, 1, "first round should be id 1");

        ILlamaGuardOracle.RiskParameterUpdate memory got =
            oracle.getLatestUpdateByParameterAndMarket(UPDATE_TYPE_EMA, ptMarket);
        assertEq(got.updateType, UPDATE_TYPE_EMA);
        assertEq(keccak256(got.additionalData), keccak256(additionalData));
        assertEq(keccak256(got.newValue), keccak256(abi.encode(emaRaw)));
        assertEq(got.market, ptMarket);
        assertEq(oracle.latestAnswer(), emaRaw, "oracle.latestAnswer mismatch");
        assertEq(oracle.decimals(), 18, "oracle decimals mismatch");
    }

    // ════════════════════════════════════════════════════════════════════════
    // REVERT PATHS
    // ════════════════════════════════════════════════════════════════════════

    /// @dev Only the receiver proxy holds WRITER_ROLE; direct writers must be
    ///      rejected by the access controller even if everything else is
    ///      well-formed.
    function test_directUpdateRevertsForNonWriter() public {
        address attacker = makeAddr("attacker");
        ILlamaGuardOracle.UpdateInput memory input = ILlamaGuardOracle.UpdateInput({
            referenceId: "bypass-1",
            newValue: abi.encode(int256(1e16)),
            updateType: UPDATE_TYPE_EMA,
            additionalData: _encodeEmaAdditionalData(int256(1e16), block.timestamp),
            deadline: block.timestamp + 1 hours
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, attacker, oracle.WRITER_ROLE()
            )
        );
        vm.prank(attacker);
        oracle.updateLatestRiskRoundData(input);
    }

    /// @dev `onReport` from anyone but the configured forwarder reverts.
    function test_onReportRevertsForNonForwarder() public {
        bytes memory metadata = _buildMetadata(workflowId, workflowName, author);
        bytes memory report = _encodeUpdateInput(
            "fwd-x", int256(1e16), _encodeEmaAdditionalData(int256(1e16), block.timestamp), block.timestamp + 1 hours
        );

        address impostor = makeAddr("impostor-forwarder");
        vm.prank(impostor);
        vm.expectRevert(abi.encodeWithSelector(AbstractCreReceiver.InvalidForwarder.selector, impostor, forwarder));
        receiverProxy.onReport(metadata, report);
    }

    /// @dev A report whose metadata workflowId does not match any active
    ///      config reverts with `WorkflowNotActive` (the lookup hits an
    ///      uninitialised slot with `isActive == false`).
    function test_onReportRevertsForWrongWorkflowId() public {
        bytes32 wrongWorkflowId = bytes32(uint256(0xBADBAD));
        bytes memory metadata = _buildMetadata(wrongWorkflowId, workflowName, author);
        bytes memory report = _encodeUpdateInput(
            "wf-x", int256(1e16), _encodeEmaAdditionalData(int256(1e16), block.timestamp), block.timestamp + 1 hours
        );

        vm.prank(forwarder);
        vm.expectRevert(abi.encodeWithSelector(AbstractCreReceiver.WorkflowNotActive.selector, wrongWorkflowId));
        receiverProxy.onReport(metadata, report);
    }

    /// @dev A report whose `deadline` has already passed must be rejected by
    ///      the oracle layer.
    function test_onReportRevertsForExpiredDeadline() public {
        uint256 staleDeadline = block.timestamp - 1;
        bytes memory metadata = _buildMetadata(workflowId, workflowName, author);
        bytes memory report = _encodeUpdateInput(
            "stale-1", int256(1e16), _encodeEmaAdditionalData(int256(1e16), block.timestamp), staleDeadline
        );

        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(ILlamaGuardOracle.DeadlineExpired.selector, staleDeadline, block.timestamp)
        );
        receiverProxy.onReport(metadata, report);
    }

    // ════════════════════════════════════════════════════════════════════════
    // HELPERS
    // ════════════════════════════════════════════════════════════════════════

    function _encodeUpdateInput(
        string memory referenceId,
        int256 emaRaw,
        bytes memory additionalData,
        uint256 deadline
    )
        internal
        pure
        returns (bytes memory)
    {
        ILlamaGuardOracle.UpdateInput memory input = ILlamaGuardOracle.UpdateInput({
            referenceId: referenceId,
            newValue: abi.encode(emaRaw),
            updateType: UPDATE_TYPE_EMA,
            additionalData: additionalData,
            deadline: deadline
        });
        return abi.encode(input);
    }

    /// @dev Realistic 8-field additionalData bundle for an EMA round. Values
    ///      are placeholders chosen to be distinct from the headline EMA so a
    ///      reader can tell `newValue` and `additionalData` apart in logs.
    function _encodeEmaAdditionalData(int256 emaRaw, uint256 observedAt) internal pure returns (bytes memory) {
        return abi.encode(
            emaRaw, // implied rate raw (matches newValue)
            uint256(int256(emaRaw) * int256(99) / int256(100)), // ema lower bound, 99% of raw
            uint256(int256(emaRaw) * int256(101) / int256(100)), // ema upper bound, 101% of raw
            uint256(120), // sample window seconds
            uint256(observedAt), // observation timestamp
            uint256(1_000_000_000_000_000_000), // pt scale anchor (1e18)
            uint256(7_776_000), // PT remaining maturity seconds
            uint256(0) // reserved
        );
    }

    function _buildMetadata(
        bytes32 _workflowId,
        bytes10 _workflowName,
        address _author
    )
        internal
        pure
        returns (bytes memory)
    {
        bytes memory out = new bytes(62);
        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(add(out, 32), _workflowId)
            mstore(add(out, 64), _workflowName)
            mstore(add(out, 74), shl(96, _author))
        }
        return out;
    }
}
