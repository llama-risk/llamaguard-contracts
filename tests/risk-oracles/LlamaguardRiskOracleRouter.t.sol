// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { Test, Vm } from "forge-std/Test.sol";
import { LlamaguardRiskOracleRouter } from "../../src/LlamaguardRiskOracleRouter.sol";
import { AbstractRoutedCreReceiver } from "../../src/abstracts/AbstractRoutedCreReceiver.sol";
import { IAgentHub } from "../../src/interfaces/IAgentHub.sol";
import { MockRiskOracleSink } from "./mocks/MockRiskOracleSink.sol";
import { MockAgentHub } from "./mocks/MockAgentHub.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { RouterSelectors } from "../../script/risk-oracles/RouterSelectors.sol";

contract MetadataDecodeHarness is AbstractRoutedCreReceiver {
    function decodeMetadata(bytes memory metadata)
        external
        pure
        returns (bytes32 workflowId, address workflowOwner, bytes10 workflowName)
    {
        return _getWorkflowMetaData(metadata);
    }

    function _processReport(bytes32, bytes calldata) internal pure override { }
}

contract LlamaguardRiskOracleRouterTest is Test {
    LlamaguardRiskOracleRouter internal router;
    MockRiskOracleSink internal sinkA;
    MockRiskOracleSink internal sinkB;
    MockAgentHub internal hub;

    address internal owner = makeAddr("owner");
    address internal updater = makeAddr("updater");
    address internal forwarder = makeAddr("forwarder");
    address internal author = makeAddr("author");
    address internal rando = makeAddr("rando");

    bytes32 internal workflowIdA = bytes32(uint256(0xA));
    bytes32 internal workflowIdB = bytes32(uint256(0xB));
    bytes10 internal workflowName = bytes10("pt_dr_v1__");
    bytes4 internal selectorA = bytes4(keccak256("publishRiskParameterUpdate(bytes)"));
    bytes4 internal selectorB = bytes4(keccak256("publishBulkRiskParameterUpdates(bytes)"));

    function setUp() public {
        router = new LlamaguardRiskOracleRouter(owner);
        sinkA = new MockRiskOracleSink();
        sinkB = new MockRiskOracleSink();
        hub = new MockAgentHub();

        vm.prank(owner);
        router.setUpdater(updater);
    }

    // ============================================================================================
    // Helpers
    // ============================================================================================

    function _buildMetadata(bytes32 workflowId, bytes10 name, address authorAddr) internal pure returns (bytes memory) {
        // Mirror AbstractRoutedCreReceiver._getWorkflowMetaData layout:
        //   offset 0:  bytes32 workflowId
        //   offset 32: bytes10 workflowName (high 10 bytes of word)
        //   offset 42: address author (20 bytes)
        bytes memory out = new bytes(62);
        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(add(out, 32), workflowId)
            mstore(add(out, 64), name)
            mstore(add(out, 74), shl(96, authorAddr))
        }
        return out;
    }

    function _slice(bytes memory input, uint256 start, uint256 end) internal pure returns (bytes memory output) {
        output = new bytes(end - start);
        for (uint256 i; i < output.length; ++i) {
            output[i] = input[start + i];
        }
    }

    function _singletonAgentIds(uint256 id) internal pure returns (uint256[] memory ids) {
        ids = new uint256[](1);
        ids[0] = id;
    }

    function _seedRouteA(address agentHub_) internal {
        vm.prank(owner);
        router.addRoute({
            workflowId: workflowIdA,
            forwarder: forwarder,
            author: author,
            workflowName: workflowName,
            riskOracle: address(sinkA),
            publishSelector: selectorA,
            agentHub: agentHub_,
            agentIds: agentHub_ == address(0) ? new uint256[](0) : _singletonAgentIds(7),
            maxReportAgeSeconds: 0
        });
    }

    function _programHubHappyPath() internal {
        // Default action set for happy-path tests: one action against agentId 7, no markets.
        IAgentHub.ActionData[] memory actions = new IAgentHub.ActionData[](1);
        actions[0] = IAgentHub.ActionData({ agentId: 7, markets: new address[](0) });
        hub.setCheckReturn(true, actions);
    }

    // ============================================================================================
    // Constructor & access control
    // ============================================================================================

    function test_realForwarderReport_matchesAbstractCreReceiverLayout() public {
        // Plasma KeystoneForwarder report tx:
        // https://plasmascan.to/tx/0x2cc39728a83873bde005008df08c118fd1225d270c69163386c9583705a9a2f4
        // Its trace shows onReport(metadata, report) receiving rawReport[45:109]
        // and rawReport[109:] byte-for-byte. The last two metadata bytes are reportId.
        bytes memory rawReport = bytes.concat(
            hex"0156533d588c392936062594e5eec0ef0fad218218189a47f84d6ffcd76713fd",
            hex"7a6a560d6f000000010000000100d6a16ac896b86ad0bca59ababa7d7db5cdd3",
            hex"4b1677c07b7255e200bf3b6b6533343938663466626161180b3abc1adf56d82f",
            hex"c94e49078c0267a18e51ff000000000000000000000000000000000000000000",
            hex"0000000000000000006a560d6e"
        );
        bytes memory metadata = _slice(rawReport, 45, 109);
        bytes memory report = _slice(rawReport, 109, rawReport.length);

        bytes32 expectedWorkflowId = hex"00d6a16ac896b86ad0bca59ababa7d7db5cdd34b1677c07b7255e200bf3b6b65";
        bytes10 expectedWorkflowName = bytes10(hex"33343938663466626161");
        address expectedWorkflowOwner = address(bytes20(hex"180b3abc1adf56d82fc94e49078c0267a18e51ff"));

        MetadataDecodeHarness harness = new MetadataDecodeHarness();
        (bytes32 workflowId, address workflowOwner, bytes10 decodedWorkflowName) = harness.decodeMetadata(metadata);

        assertEq(metadata.length, 64);
        assertEq(report, hex"000000000000000000000000000000000000000000000000000000006a560d6e");
        assertEq(workflowId, expectedWorkflowId);
        assertEq(decodedWorkflowName, expectedWorkflowName);
        assertEq(workflowOwner, expectedWorkflowOwner);
    }

    function test_constructor_setsOwnerOnly_updaterStartsZero() public {
        LlamaguardRiskOracleRouter fresh = new LlamaguardRiskOracleRouter(owner);
        assertEq(fresh.owner(), owner);
        assertEq(fresh.updater(), address(0));
    }

    function test_setUpdater_onlyOwner() public {
        vm.prank(rando);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, rando));
        router.setUpdater(rando);

        vm.prank(owner);
        router.setUpdater(rando);
        assertEq(router.updater(), rando);
    }

    function test_setUpdater_revertsOnZero() public {
        vm.prank(owner);
        vm.expectRevert(LlamaguardRiskOracleRouter.ZeroAddress.selector);
        router.setUpdater(address(0));
    }

    function test_setUpdater_emitsUpdaterChanged() public {
        vm.recordLogs();
        vm.prank(owner);
        router.setUpdater(rando);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256("UpdaterChanged(address,address)");
        bool found;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] == topic) {
                assertEq(address(uint160(uint256(logs[i].topics[1]))), updater); // previous
                assertEq(address(uint160(uint256(logs[i].topics[2]))), rando); // new
                found = true;
            }
        }
        assertTrue(found, "UpdaterChanged not emitted");
    }

    // ============================================================================================
    // Route lifecycle
    // ============================================================================================

    function test_addRoute_storesBothMappings() public {
        _seedRouteA(address(hub));
        (address riskOracle, bytes4 sel, address ah, bool enabled,,,) = router.routes(workflowIdA);
        assertEq(riskOracle, address(sinkA));
        assertEq(sel, selectorA);
        assertEq(ah, address(hub));
        assertTrue(enabled);

        uint256[] memory ids = router.getAgentIds(workflowIdA);
        assertEq(ids.length, 1);
        assertEq(ids[0], 7);

        AbstractRoutedCreReceiver.WorkflowConfig memory cfg = router.getWorkflowConfig(workflowIdA);
        assertEq(cfg.expectedForwarder, forwarder);
        assertEq(cfg.expectedAuthor, author);
        assertEq(bytes10(cfg.expectedWorkflowName), workflowName);
        assertTrue(cfg.isActive);
    }

    function test_addRoute_revertsOnDuplicate() public {
        _seedRouteA(address(hub));
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(LlamaguardRiskOracleRouter.RouteAlreadyExists.selector, workflowIdA));
        router.addRoute(
            workflowIdA, forwarder, author, workflowName, address(sinkA), selectorA, address(0), new uint256[](0), 0
        );
    }

    function test_addRoute_revertsOnZeroOracle() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(LlamaguardRiskOracleRouter.InvalidRiskOracle.selector, address(0)));
        router.addRoute(
            workflowIdA, forwarder, author, workflowName, address(0), selectorA, address(0), new uint256[](0), 0
        );
    }

    function test_addRoute_revertsOnInvalidOracle_noContract() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(LlamaguardRiskOracleRouter.InvalidRiskOracle.selector, address(1)));
        router.addRoute(
            workflowIdA, forwarder, author, workflowName, address(1), selectorA, address(0), new uint256[](0), 0
        );
    }

    function test_addRoute_revertsOnZeroSelector() public {
        vm.prank(owner);
        vm.expectRevert(LlamaguardRiskOracleRouter.ZeroSelector.selector);
        router.addRoute(
            workflowIdA, forwarder, author, workflowName, address(sinkA), bytes4(0), address(0), new uint256[](0), 0
        );
    }

    function test_addRoute_revertsOnZeroForwarder() public {
        vm.prank(owner);
        vm.expectRevert(LlamaguardRiskOracleRouter.ZeroAddress.selector);
        router.addRoute(
            workflowIdA, address(0), author, workflowName, address(sinkA), selectorA, address(0), new uint256[](0), 0
        );
    }

    function test_addRoute_revertsOnZeroAuthor() public {
        vm.prank(owner);
        vm.expectRevert(LlamaguardRiskOracleRouter.ZeroAddress.selector);
        router.addRoute(
            workflowIdA, forwarder, address(0), workflowName, address(sinkA), selectorA, address(0), new uint256[](0), 0
        );
    }

    function test_addRoute_revertsOnZeroWorkflowName() public {
        vm.prank(owner);
        vm.expectRevert(LlamaguardRiskOracleRouter.ZeroWorkflowName.selector);
        router.addRoute(
            workflowIdA, forwarder, author, bytes10(0), address(sinkA), selectorA, address(0), new uint256[](0), 0
        );
    }

    function test_addRoute_revertsWhenHubSetButAgentIdsEmpty() public {
        vm.prank(owner);
        vm.expectRevert(LlamaguardRiskOracleRouter.EmptyAgentIds.selector);
        router.addRoute(
            workflowIdA, forwarder, author, workflowName, address(sinkA), selectorA, address(hub), new uint256[](0), 0
        );
    }

    function test_removeRouteThenReAdd_succeeds() public {
        _seedRouteA(address(hub));
        vm.prank(owner);
        router.removeRoute(workflowIdA);

        _seedRouteA(address(hub));
        (address riskOracle,,, bool enabled,,,) = router.routes(workflowIdA);
        assertEq(riskOracle, address(sinkA));
        assertTrue(enabled);
        assertTrue(router.getWorkflowConfig(workflowIdA).isActive);
    }

    function test_removeRoute_clearsBothMappings() public {
        _seedRouteA(address(hub));
        vm.prank(owner);
        router.removeRoute(workflowIdA);

        (address riskOracle,,,,,,) = router.routes(workflowIdA);
        assertEq(riskOracle, address(0));
        AbstractRoutedCreReceiver.WorkflowConfig memory cfg = router.getWorkflowConfig(workflowIdA);
        assertEq(cfg.expectedForwarder, address(0));
        assertFalse(cfg.isActive);
        assertEq(router.getAgentIds(workflowIdA).length, 0);
    }

    function test_setRiskOracle_revertsForNonOwner_andUpdatesTarget() public {
        _seedRouteA(address(hub));
        vm.prank(rando);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, rando));
        router.setRiskOracle(workflowIdA, address(sinkB), selectorB);

        vm.prank(owner);
        router.setRiskOracle(workflowIdA, address(sinkB), selectorB);
        (address riskOracle, bytes4 sel,,,,,) = router.routes(workflowIdA);
        assertEq(riskOracle, address(sinkB));
        assertEq(sel, selectorB);
    }

    function test_setAgentHub_canZeroOut() public {
        _seedRouteA(address(hub));
        vm.prank(owner);
        router.setAgentHub(workflowIdA, address(0));
        (,, address ah,,,,) = router.routes(workflowIdA);
        assertEq(ah, address(0));
    }

    function test_setAgentHub_revertsForNonOwner() public {
        _seedRouteA(address(hub));
        vm.prank(rando);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, rando));
        router.setAgentHub(workflowIdA, address(0));
    }

    function test_setAgentHub_revertsOnUnknownRoute() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(LlamaguardRiskOracleRouter.RouteNotFound.selector, workflowIdA));
        router.setAgentHub(workflowIdA, address(hub));
    }

    function test_setAgentHub_revertsIfEnablingWithoutAgentIds() public {
        // Seed a route with no hub and empty agentIds, then try to enable injection without
        // first configuring an agent set.
        _seedRouteA(address(0));
        assertEq(router.getAgentIds(workflowIdA).length, 0);

        vm.prank(owner);
        vm.expectRevert(LlamaguardRiskOracleRouter.EmptyAgentIds.selector);
        router.setAgentHub(workflowIdA, address(hub));
    }

    function test_setRiskOracle_revertsOnZeroOracle() public {
        _seedRouteA(address(hub));
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(LlamaguardRiskOracleRouter.InvalidRiskOracle.selector, address(0)));
        router.setRiskOracle(workflowIdA, address(0), selectorA);
    }

    function test_setRiskOracle_revertsOnInvalidOracle_noContract() public {
        _seedRouteA(address(hub));
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(LlamaguardRiskOracleRouter.InvalidRiskOracle.selector, address(1)));
        router.setRiskOracle(workflowIdA, address(1), selectorA);
    }

    function test_setRiskOracle_revertsOnZeroSelector() public {
        _seedRouteA(address(hub));
        vm.prank(owner);
        vm.expectRevert(LlamaguardRiskOracleRouter.ZeroSelector.selector);
        router.setRiskOracle(workflowIdA, address(sinkB), bytes4(0));
    }

    function test_setRiskOracle_revertsOnUnknownRoute() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(LlamaguardRiskOracleRouter.RouteNotFound.selector, workflowIdA));
        router.setRiskOracle(workflowIdA, address(sinkB), selectorB);
    }

    function test_setRouteEnabled_onlyUpdater_andTogglesIsActive() public {
        _seedRouteA(address(hub));
        vm.prank(rando);
        vm.expectRevert(LlamaguardRiskOracleRouter.OnlyUpdater.selector);
        router.setRouteEnabled(workflowIdA, false);

        vm.prank(updater);
        router.setRouteEnabled(workflowIdA, false);
        (,,, bool enabled,,,) = router.routes(workflowIdA);
        assertFalse(enabled);
        assertFalse(router.getWorkflowConfig(workflowIdA).isActive);
    }

    function test_setAgentIds_onlyUpdater_andReplacesArray() public {
        _seedRouteA(address(hub));

        uint256[] memory next = new uint256[](3);
        next[0] = 1;
        next[1] = 2;
        next[2] = 99;

        vm.prank(rando);
        vm.expectRevert(LlamaguardRiskOracleRouter.OnlyUpdater.selector);
        router.setAgentIds(workflowIdA, next);

        vm.prank(updater);
        router.setAgentIds(workflowIdA, next);
        uint256[] memory got = router.getAgentIds(workflowIdA);
        assertEq(got.length, 3);
        assertEq(got[2], 99);
    }

    function test_setAgentIds_revertsOnEmptyWhenHubEnabled() public {
        _seedRouteA(address(hub));
        vm.prank(updater);
        vm.expectRevert(LlamaguardRiskOracleRouter.EmptyAgentIds.selector);
        router.setAgentIds(workflowIdA, new uint256[](0));
    }

    function test_setAgentIds_acceptsEmptyWhenHubDisabled() public {
        _seedRouteA(address(0));
        vm.prank(updater);
        router.setAgentIds(workflowIdA, new uint256[](0));
        assertEq(router.getAgentIds(workflowIdA).length, 0);
    }

    // ============================================================================================
    // Routing — happy path
    // ============================================================================================

    function test_onReport_happyPath_publishesAndDrivesAgentHub() public {
        _seedRouteA(address(hub));
        _programHubHappyPath();

        bytes memory report = abi.encode(uint256(123), uint256(456));
        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);

        vm.prank(forwarder);
        router.onReport(metadata, report);

        assertEq(sinkA.callCount(), 1);
        assertEq(sinkA.lastSelector(), selectorA);
        bytes memory received = sinkA.lastCalldata();
        assertEq(received.length, 4 + report.length);
        for (uint256 i; i < report.length; i++) {
            assertEq(received[i + 4], report[i]);
        }

        assertEq(hub.executeCallCount(), 1);
        assertEq(hub.lastExecuteActionCount(), 1);
        assertEq(hub.lastExecuteAgentId(0), 7);
    }

    function test_onReport_noAgentHub_skipsKick() public {
        _seedRouteA(address(0));
        bytes memory report = hex"deadbeef";
        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);
        vm.prank(forwarder);
        router.onReport(metadata, report);
        assertEq(sinkA.callCount(), 1);
        assertEq(hub.executeCallCount(), 0);
    }

    function test_onReport_checkReturnsShouldExecuteFalse_emitsSkip() public {
        _seedRouteA(address(hub));
        // Default check return: (false, []) — skip.
        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);

        vm.recordLogs();
        vm.prank(forwarder);
        router.onReport(metadata, hex"00");

        // Publish landed
        assertEq(sinkA.callCount(), 1);
        // execute() never invoked
        assertEq(hub.executeCallCount(), 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256("AgentHubKickSkipped(bytes32,string)");
        bool found;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] == topic && logs[i].topics[1] == workflowIdA) {
                found = true;
            }
        }
        assertTrue(found, "AgentHubKickSkipped not emitted");
    }

    // ============================================================================================
    // Routing — gatekeeping
    // ============================================================================================

    function test_onReport_revertsForWrongForwarder() public {
        _seedRouteA(address(hub));
        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);
        vm.prank(rando);
        vm.expectRevert(abi.encodeWithSelector(AbstractRoutedCreReceiver.InvalidForwarder.selector, rando, forwarder));
        router.onReport(metadata, hex"00");
    }

    function test_onReport_revertsForWrongAuthor() public {
        _seedRouteA(address(hub));
        address wrongAuthor = makeAddr("wrongAuthor");
        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, wrongAuthor);
        vm.prank(forwarder);
        vm.expectRevert(abi.encodeWithSelector(AbstractRoutedCreReceiver.InvalidAuthor.selector, wrongAuthor, author));
        router.onReport(metadata, hex"00");
    }

    function test_onReport_revertsForWrongWorkflowName() public {
        _seedRouteA(address(hub));
        bytes10 wrongName = bytes10("xx________");
        bytes memory metadata = _buildMetadata(workflowIdA, wrongName, author);
        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(AbstractRoutedCreReceiver.InvalidWorkflowName.selector, wrongName, workflowName)
        );
        router.onReport(metadata, hex"00");
    }

    function test_onReport_revertsForUnknownWorkflowId() public {
        _seedRouteA(address(hub));
        bytes memory metadata = _buildMetadata(workflowIdB, workflowName, author);
        vm.prank(forwarder);
        vm.expectRevert(abi.encodeWithSelector(AbstractRoutedCreReceiver.WorkflowNotActive.selector, workflowIdB));
        router.onReport(metadata, hex"00");
    }

    function test_onReport_revertsWhenRouteDisabled() public {
        _seedRouteA(address(hub));
        vm.prank(updater);
        router.setRouteEnabled(workflowIdA, false);
        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);
        vm.prank(forwarder);
        vm.expectRevert(abi.encodeWithSelector(AbstractRoutedCreReceiver.WorkflowNotActive.selector, workflowIdA));
        router.onReport(metadata, hex"00");
    }

    // ============================================================================================
    // Routing — error propagation
    // ============================================================================================

    function test_onReport_bubblesPublishRevert() public {
        _seedRouteA(address(hub));
        sinkA.setShouldRevert(true, "boom");
        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);

        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(LlamaguardRiskOracleRouter.PublishFailed.selector, workflowIdA, bytes("boom"))
        );
        router.onReport(metadata, hex"00");

        assertEq(sinkA.callCount(), 0); // sink reverted before incrementing
        assertEq(hub.executeCallCount(), 0); // injection never fires when publish reverts
    }

    function test_onReport_catchesCheckRevert_publishStillStands() public {
        _seedRouteA(address(hub));
        hub.setCheckShouldRevert(true, "check-boom");
        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);

        vm.recordLogs();
        vm.prank(forwarder);
        router.onReport(metadata, hex"deadbeef");

        // Publish landed
        assertEq(sinkA.callCount(), 1);
        // execute() never invoked
        assertEq(hub.executeCallCount(), 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256("AgentHubKickResultFailed(bytes32,bytes)");
        bool found;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] == topic && logs[i].topics[1] == workflowIdA) {
                bytes memory ret = abi.decode(logs[i].data, (bytes));
                assertEq(ret, bytes("check-boom"));
                found = true;
            }
        }
        assertTrue(found, "AgentHubKickResultFailed not emitted");
    }

    function test_onReport_catchesExecuteRevert_publishStillStands() public {
        _seedRouteA(address(hub));
        _programHubHappyPath();
        hub.setExecuteShouldRevert(true, "exec-boom");
        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);

        vm.recordLogs();
        vm.prank(forwarder);
        router.onReport(metadata, hex"deadbeef");

        assertEq(sinkA.callCount(), 1);
        assertEq(hub.executeCallCount(), 0); // execute reverted; counter not incremented

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256("AgentHubKickResultFailed(bytes32,bytes)");
        bool found;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] == topic && logs[i].topics[1] == workflowIdA) {
                bytes memory ret = abi.decode(logs[i].data, (bytes));
                assertEq(ret, bytes("exec-boom"));
                found = true;
            }
        }
        assertTrue(found, "AgentHubKickResultFailed not emitted");
    }

    // ============================================================================================
    // Multi-route isolation
    // ============================================================================================

    function test_multiRoute_disablingOneDoesNotAffectOther() public {
        _seedRouteA(address(hub));
        vm.prank(owner);
        router.addRoute(
            workflowIdB, forwarder, author, workflowName, address(sinkB), selectorB, address(0), new uint256[](0), 0
        );

        vm.prank(updater);
        router.setRouteEnabled(workflowIdA, false);

        bytes memory metadata = _buildMetadata(workflowIdB, workflowName, author);
        vm.prank(forwarder);
        router.onReport(metadata, hex"00");
        assertEq(sinkB.callCount(), 1);
    }

    // ============================================================================================
    // Edge cases — publish revert with empty returndata
    // ============================================================================================

    function test_onReport_publishFailsWithEmptyReturndata() public {
        _seedRouteA(address(hub));
        sinkA.setShouldRevert(true, "");
        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);

        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(LlamaguardRiskOracleRouter.PublishFailed.selector, workflowIdA, bytes(""))
        );
        router.onReport(metadata, hex"deadbeef");

        assertEq(hub.executeCallCount(), 0);
    }

    // ============================================================================================
    // Single vs bulk selector parity
    // ============================================================================================

    /// @dev The router is selector-agnostic for the oracle write: the same code path handles
    ///      both single and bulk variants. The workflow operator picks the variant by
    ///      registering the matching selector.
    function test_onReport_routesSingleAndBulkSelectors_identically() public {
        _seedRouteA(address(0));

        vm.prank(owner);
        router.addRoute(
            workflowIdB, forwarder, author, workflowName, address(sinkB), selectorB, address(0), new uint256[](0), 0
        );

        bytes memory singleReport = abi.encode(uint256(7));
        bytes memory metaA = _buildMetadata(workflowIdA, workflowName, author);
        vm.prank(forwarder);
        router.onReport(metaA, singleReport);

        uint256[] memory arr = new uint256[](3);
        arr[0] = 1;
        arr[1] = 2;
        arr[2] = 3;
        bytes memory bulkReport = abi.encode(arr);
        bytes memory metaB = _buildMetadata(workflowIdB, workflowName, author);
        vm.prank(forwarder);
        router.onReport(metaB, bulkReport);

        assertEq(sinkA.callCount(), 1);
        assertEq(sinkA.lastSelector(), selectorA);
        assertEq(sinkA.lastCalldata().length, 4 + singleReport.length);

        assertEq(sinkB.callCount(), 1);
        assertEq(sinkB.lastSelector(), selectorB);
        assertEq(sinkB.lastCalldata().length, 4 + bulkReport.length);
    }

    // ============================================================================================
    // Fuzz — arbitrary report bytes survive the round-trip
    // ============================================================================================

    function testFuzz_onReport_forwardsArbitraryReport(bytes calldata report) public {
        _seedRouteA(address(0));
        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);

        vm.prank(forwarder);
        router.onReport(metadata, report);

        assertEq(sinkA.callCount(), 1);
        assertEq(sinkA.lastSelector(), selectorA);
        bytes memory got = sinkA.lastCalldata();
        assertEq(got.length, 4 + report.length);
        for (uint256 i; i < report.length; i++) {
            assertEq(got[i + 4], report[i]);
        }
    }

    // ============================================================================================
    // Throttle — setter access control and validation
    // ============================================================================================

    string internal constant TYPE_DR = "PendleDiscountRateUpdate";
    address internal market1 = makeAddr("market1");
    address internal market2 = makeAddr("market2");
    address internal market3 = makeAddr("market3");

    function _seedThrottledSingleRoute(bytes32 workflowId, address sink) internal {
        vm.prank(owner);
        router.addRoute({
            workflowId: workflowId,
            forwarder: forwarder,
            author: author,
            workflowName: workflowName,
            riskOracle: sink,
            publishSelector: RouterSelectors.PUBLISH_SINGLE_SELECTOR,
            agentHub: address(0),
            agentIds: new uint256[](0),
            maxReportAgeSeconds: 0
        });
    }

    function _seedThrottledBulkRoute(bytes32 workflowId, address sink) internal {
        vm.prank(owner);
        router.addRoute({
            workflowId: workflowId,
            forwarder: forwarder,
            author: author,
            workflowName: workflowName,
            riskOracle: sink,
            publishSelector: RouterSelectors.PUBLISH_BULK_SELECTOR,
            agentHub: address(0),
            agentIds: new uint256[](0),
            maxReportAgeSeconds: 0
        });
    }

    function _singleReport(
        string memory refId,
        uint256 newValue,
        string memory updateType,
        address market
    )
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(refId, abi.encode(newValue), updateType, market, bytes(""));
    }

    function _singleReportRaw(
        string memory refId,
        bytes memory newValueBytes,
        string memory updateType,
        address market
    )
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(refId, newValueBytes, updateType, market, bytes(""));
    }

    function test_setRouteThrottle_onlyUpdater_revertsOnNonUpdater() public {
        _seedThrottledSingleRoute(workflowIdA, address(sinkA));
        vm.prank(rando);
        vm.expectRevert(LlamaguardRiskOracleRouter.OnlyUpdater.selector);
        router.setRouteThrottle(workflowIdA, 1800, 500);
    }

    function test_setRouteThrottle_revertsOnBpsTooHigh() public {
        _seedThrottledSingleRoute(workflowIdA, address(sinkA));
        vm.prank(updater);
        vm.expectRevert(abi.encodeWithSelector(LlamaguardRiskOracleRouter.BpsTooHigh.selector, uint64(10_001)));
        router.setRouteThrottle(workflowIdA, 1800, 10_001);
    }

    function test_setRouteThrottle_revertsOnUnknownRoute() public {
        vm.prank(updater);
        vm.expectRevert(abi.encodeWithSelector(LlamaguardRiskOracleRouter.RouteNotFound.selector, workflowIdA));
        router.setRouteThrottle(workflowIdA, 1800, 500);
    }

    function test_setRouteThrottle_emitsEventAndStoresValues() public {
        _seedThrottledSingleRoute(workflowIdA, address(sinkA));

        vm.recordLogs();
        vm.prank(updater);
        router.setRouteThrottle(workflowIdA, 1800, 500);

        (,,,, uint64 minDelay, uint64 maxStep,) = router.routes(workflowIdA);
        assertEq(minDelay, 1800);
        assertEq(maxStep, 500);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256("RouteThrottleSet(bytes32,uint64,uint64)");
        bool found;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] == topic && logs[i].topics[1] == workflowIdA) {
                (uint64 d, uint64 s) = abi.decode(logs[i].data, (uint64, uint64));
                assertEq(d, 1800);
                assertEq(s, 500);
                found = true;
            }
        }
        assertTrue(found, "RouteThrottleSet not emitted");
    }

    // ============================================================================================
    // Throttle — min-delay
    // ============================================================================================

    function test_onReport_throttle_revertsWithinDelayWindow() public {
        _seedThrottledSingleRoute(workflowIdA, address(sinkA));
        vm.prank(updater);
        router.setRouteThrottle(workflowIdA, 1800, 0);

        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);
        bytes memory report = _singleReport("r1", 1e18, TYPE_DR, market1);

        vm.prank(forwarder);
        router.onReport(metadata, report);
        assertEq(sinkA.callCount(), 1);

        // Second publish within delay window: reverts
        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(
                LlamaguardRiskOracleRouter.ThrottleCheckFailed.selector, workflowIdA, market1, TYPE_DR
            )
        );
        router.onReport(metadata, _singleReport("r2", 1e18, TYPE_DR, market1));
        assertEq(sinkA.callCount(), 1);
    }

    function test_onReport_throttle_passesAfterDelayElapses() public {
        _seedThrottledSingleRoute(workflowIdA, address(sinkA));
        vm.prank(updater);
        router.setRouteThrottle(workflowIdA, 1800, 0);

        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);
        vm.prank(forwarder);
        router.onReport(metadata, _singleReport("r1", 1e18, TYPE_DR, market1));

        vm.warp(block.timestamp + 1800);
        vm.prank(forwarder);
        router.onReport(metadata, _singleReport("r2", 1e18, TYPE_DR, market1));
        assertEq(sinkA.callCount(), 2);
    }

    function test_onReport_throttle_perMarketUpdateTypeIsolation() public {
        _seedThrottledSingleRoute(workflowIdA, address(sinkA));
        vm.prank(updater);
        router.setRouteThrottle(workflowIdA, 1800, 0);

        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);

        vm.prank(forwarder);
        router.onReport(metadata, _singleReport("r1", 1e18, TYPE_DR, market1));
        // Different market, same updateType: must NOT be throttled.
        vm.prank(forwarder);
        router.onReport(metadata, _singleReport("r2", 1e18, TYPE_DR, market2));
        // Same market, different updateType: must NOT be throttled.
        vm.prank(forwarder);
        router.onReport(metadata, _singleReport("r3", 1e18, "OtherType", market1));

        assertEq(sinkA.callCount(), 3);
    }

    // ============================================================================================
    // Throttle — max-step
    // ============================================================================================

    function test_onReport_maxStepBps_revertsOnLargeIncrease() public {
        _seedThrottledSingleRoute(workflowIdA, address(sinkA));
        vm.prank(updater);
        router.setRouteThrottle(workflowIdA, 0, 500); // 5%

        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);
        vm.prank(forwarder);
        router.onReport(metadata, _singleReport("r1", 1e18, TYPE_DR, market1));
        assertEq(sinkA.callCount(), 1);

        // +10% delta vs 1e18 baseline → exceeds 5% bound → reverts
        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(
                LlamaguardRiskOracleRouter.ThrottleCheckFailed.selector, workflowIdA, market1, TYPE_DR
            )
        );
        router.onReport(metadata, _singleReport("r2", 11e17, TYPE_DR, market1));
        assertEq(sinkA.callCount(), 1);
    }

    function test_onReport_maxStepBps_revertsOnLargeDecrease() public {
        _seedThrottledSingleRoute(workflowIdA, address(sinkA));
        vm.prank(updater);
        router.setRouteThrottle(workflowIdA, 0, 500);

        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);
        vm.prank(forwarder);
        router.onReport(metadata, _singleReport("r1", 1e18, TYPE_DR, market1));
        assertEq(sinkA.callCount(), 1);

        // -20% delta exceeds 5% bound → reverts
        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(
                LlamaguardRiskOracleRouter.ThrottleCheckFailed.selector, workflowIdA, market1, TYPE_DR
            )
        );
        router.onReport(metadata, _singleReport("r2", 8e17, TYPE_DR, market1));
        assertEq(sinkA.callCount(), 1);
    }

    function test_onReport_maxStepBps_passesWithinBound() public {
        _seedThrottledSingleRoute(workflowIdA, address(sinkA));
        vm.prank(updater);
        router.setRouteThrottle(workflowIdA, 0, 1000); // 10%

        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);
        vm.prank(forwarder);
        router.onReport(metadata, _singleReport("r1", 1e18, TYPE_DR, market1));

        vm.prank(forwarder);
        router.onReport(metadata, _singleReport("r2", 105e16, TYPE_DR, market1)); // +5%
        assertEq(sinkA.callCount(), 2);

        LlamaguardRiskOracleRouter.UpdateRecord memory rec = router.getUpdateRecord(workflowIdA, market1, TYPE_DR);
        assertEq(rec.lastValue, 105e16);
    }

    function test_onReport_maxStepBps_firstPublishAlwaysLands() public {
        _seedThrottledSingleRoute(workflowIdA, address(sinkA));
        vm.prank(updater);
        router.setRouteThrottle(workflowIdA, 0, 1); // absurdly tight 0.01%

        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);
        vm.prank(forwarder);
        router.onReport(metadata, _singleReport("r1", 1e18, TYPE_DR, market1));
        // First publish always lands (no prior value to compare to).
        assertEq(sinkA.callCount(), 1);

        LlamaguardRiskOracleRouter.UpdateRecord memory rec = router.getUpdateRecord(workflowIdA, market1, TYPE_DR);
        assertEq(rec.lastValue, 1e18);
    }

    function test_onReport_maxStepBps_skippedWhenNewValueIsNot32Bytes() public {
        _seedThrottledSingleRoute(workflowIdA, address(sinkA));
        vm.prank(updater);
        router.setRouteThrottle(workflowIdA, 1800, 1); // tight delta — but tuple payload bypasses it

        // Tuple-shaped newValue (3 uint256s) — bypasses max-step but still triggers min-delay.
        bytes memory tupleValue = abi.encode(uint256(1), uint256(2), uint256(3));
        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);

        vm.prank(forwarder);
        router.onReport(metadata, _singleReportRaw("r1", tupleValue, TYPE_DR, market1));
        assertEq(sinkA.callCount(), 1);

        // lastValue stayed 0 (non-scalar shape) — but lastAt was recorded for min-delay.
        LlamaguardRiskOracleRouter.UpdateRecord memory rec = router.getUpdateRecord(workflowIdA, market1, TYPE_DR);
        assertEq(rec.lastValue, 0);
        assertEq(rec.lastAt, uint64(block.timestamp));

        // Second publish within delay: reverts due to min-delay despite tuple shape.
        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(
                LlamaguardRiskOracleRouter.ThrottleCheckFailed.selector, workflowIdA, market1, TYPE_DR
            )
        );
        router.onReport(metadata, _singleReportRaw("r2", tupleValue, TYPE_DR, market1));
        assertEq(sinkA.callCount(), 1);
    }

    // ============================================================================================
    // Throttle — bulk
    // ============================================================================================

    function test_onReport_bulk_anyElementTrip_revertsWholeBatch() public {
        _seedThrottledBulkRoute(workflowIdA, address(sinkA));
        vm.prank(updater);
        router.setRouteThrottle(workflowIdA, 1800, 0);

        // Prime market2 with a recent publish via a single-element bulk.
        {
            string[] memory refIds = new string[](1);
            bytes[] memory newValues = new bytes[](1);
            string[] memory updateTypes = new string[](1);
            address[] memory markets = new address[](1);
            bytes[] memory additionalData = new bytes[](1);
            refIds[0] = "r0";
            newValues[0] = abi.encode(uint256(1e18));
            updateTypes[0] = TYPE_DR;
            markets[0] = market2;
            additionalData[0] = bytes("");
            bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);
            vm.prank(forwarder);
            router.onReport(metadata, abi.encode(refIds, newValues, updateTypes, markets, additionalData));
        }
        assertEq(sinkA.callCount(), 1);

        // Now send a bulk with market1 (untouched, would pass) followed by market2 (just
        // touched — would trip min-delay). Whole batch must revert when market2 fails.
        string[] memory refIds2 = new string[](2);
        bytes[] memory newValues2 = new bytes[](2);
        string[] memory updateTypes2 = new string[](2);
        address[] memory markets2 = new address[](2);
        bytes[] memory additionalData2 = new bytes[](2);
        refIds2[0] = "r1";
        refIds2[1] = "r2";
        newValues2[0] = abi.encode(uint256(1e18));
        newValues2[1] = abi.encode(uint256(1e18));
        updateTypes2[0] = TYPE_DR;
        updateTypes2[1] = TYPE_DR;
        markets2[0] = market1;
        markets2[1] = market2;
        additionalData2[0] = bytes("");
        additionalData2[1] = bytes("");

        // Expect revert when market2 (the second element) trips the throttle.
        vm.expectRevert(
            abi.encodeWithSelector(
                LlamaguardRiskOracleRouter.ThrottleCheckFailed.selector, workflowIdA, market2, TYPE_DR
            )
        );
        vm.prank(forwarder);
        router.onReport(
            _buildMetadata(workflowIdA, workflowName, author),
            abi.encode(refIds2, newValues2, updateTypes2, markets2, additionalData2)
        );

        // No additional publish landed due to revert.
        assertEq(sinkA.callCount(), 1);

        // Critical: market1's record must NOT have been committed due to EVM rollback.
        // The revert for market2 rolls back ALL storage changes, including market1's record.
        LlamaguardRiskOracleRouter.UpdateRecord memory rec1 = router.getUpdateRecord(workflowIdA, market1, TYPE_DR);
        assertEq(rec1.lastAt, 0, "market1 record should not be committed due to revert rollback");
    }

    function test_onReport_bulk_firstElementFails_revertsImmediately() public {
        _seedThrottledBulkRoute(workflowIdA, address(sinkA));
        vm.prank(updater);
        router.setRouteThrottle(workflowIdA, 1800, 0);

        // Prime market1 with a recent publish.
        {
            string[] memory refIds = new string[](1);
            bytes[] memory newValues = new bytes[](1);
            string[] memory updateTypes = new string[](1);
            address[] memory markets = new address[](1);
            bytes[] memory additionalData = new bytes[](1);
            refIds[0] = "r0";
            newValues[0] = abi.encode(uint256(1e18));
            updateTypes[0] = TYPE_DR;
            markets[0] = market1;
            additionalData[0] = bytes("");
            bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);
            vm.prank(forwarder);
            router.onReport(metadata, abi.encode(refIds, newValues, updateTypes, markets, additionalData));
        }
        assertEq(sinkA.callCount(), 1);

        // Bulk where FIRST element (market1) trips throttle — reverts immediately, no records written.
        string[] memory refIds2 = new string[](2);
        bytes[] memory newValues2 = new bytes[](2);
        string[] memory updateTypes2 = new string[](2);
        address[] memory markets2 = new address[](2);
        bytes[] memory additionalData2 = new bytes[](2);
        refIds2[0] = "r1";
        refIds2[1] = "r2";
        newValues2[0] = abi.encode(uint256(1e18));
        newValues2[1] = abi.encode(uint256(1e18));
        updateTypes2[0] = TYPE_DR;
        updateTypes2[1] = TYPE_DR;
        markets2[0] = market1; // This one will fail (just primed)
        markets2[1] = market2; // This one would pass
        additionalData2[0] = bytes("");
        additionalData2[1] = bytes("");

        // Expect revert when market1 (the FIRST element) trips the throttle.
        vm.expectRevert(
            abi.encodeWithSelector(
                LlamaguardRiskOracleRouter.ThrottleCheckFailed.selector, workflowIdA, market1, TYPE_DR
            )
        );
        vm.prank(forwarder);
        router.onReport(
            _buildMetadata(workflowIdA, workflowName, author),
            abi.encode(refIds2, newValues2, updateTypes2, markets2, additionalData2)
        );

        // No additional publish landed.
        assertEq(sinkA.callCount(), 1);

        // market2's record must NOT have been committed (never even reached due to early revert).
        LlamaguardRiskOracleRouter.UpdateRecord memory rec2 = router.getUpdateRecord(workflowIdA, market2, TYPE_DR);
        assertEq(rec2.lastAt, 0, "market2 record should not be committed");
    }

    function test_onReport_bulk_threeElements_middleFails_allRolledBack() public {
        _seedThrottledBulkRoute(workflowIdA, address(sinkA));
        vm.prank(updater);
        router.setRouteThrottle(workflowIdA, 1800, 0);

        // Prime market2 (the middle element) with a recent publish.
        {
            string[] memory refIds = new string[](1);
            bytes[] memory newValues = new bytes[](1);
            string[] memory updateTypes = new string[](1);
            address[] memory markets = new address[](1);
            bytes[] memory additionalData = new bytes[](1);
            refIds[0] = "r0";
            newValues[0] = abi.encode(uint256(1e18));
            updateTypes[0] = TYPE_DR;
            markets[0] = market2;
            additionalData[0] = bytes("");
            bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);
            vm.prank(forwarder);
            router.onReport(metadata, abi.encode(refIds, newValues, updateTypes, markets, additionalData));
        }
        assertEq(sinkA.callCount(), 1);

        // Bulk with 3 elements: market1 (pass), market2 (fail - primed), market3 (would pass).
        string[] memory refIds2 = new string[](3);
        bytes[] memory newValues2 = new bytes[](3);
        string[] memory updateTypes2 = new string[](3);
        address[] memory markets2 = new address[](3);
        bytes[] memory additionalData2 = new bytes[](3);
        refIds2[0] = "r1";
        refIds2[1] = "r2";
        refIds2[2] = "r3";
        newValues2[0] = abi.encode(uint256(1e18));
        newValues2[1] = abi.encode(uint256(1e18));
        newValues2[2] = abi.encode(uint256(1e18));
        updateTypes2[0] = TYPE_DR;
        updateTypes2[1] = TYPE_DR;
        updateTypes2[2] = TYPE_DR;
        markets2[0] = market1; // Would pass
        markets2[1] = market2; // Will fail (just primed)
        markets2[2] = market3; // Would pass
        additionalData2[0] = bytes("");
        additionalData2[1] = bytes("");
        additionalData2[2] = bytes("");

        // Expect revert when market2 (the MIDDLE element) trips the throttle.
        vm.expectRevert(
            abi.encodeWithSelector(
                LlamaguardRiskOracleRouter.ThrottleCheckFailed.selector, workflowIdA, market2, TYPE_DR
            )
        );
        vm.prank(forwarder);
        router.onReport(
            _buildMetadata(workflowIdA, workflowName, author),
            abi.encode(refIds2, newValues2, updateTypes2, markets2, additionalData2)
        );

        // No additional publish landed.
        assertEq(sinkA.callCount(), 1);

        // All records must NOT have been committed due to EVM rollback.
        LlamaguardRiskOracleRouter.UpdateRecord memory rec1 = router.getUpdateRecord(workflowIdA, market1, TYPE_DR);
        LlamaguardRiskOracleRouter.UpdateRecord memory rec3 = router.getUpdateRecord(workflowIdA, market3, TYPE_DR);
        assertEq(rec1.lastAt, 0, "market1 record should not be committed due to revert rollback");
        assertEq(rec3.lastAt, 0, "market3 record should not be committed (never reached)");
    }

    function test_onReport_bulk_maxStepFailsFirst_revertsBeforeMinDelayCheck() public {
        _seedThrottledBulkRoute(workflowIdA, address(sinkA));
        vm.prank(updater);
        // Set both min-delay (1800s) and max-step (500 bps = 5%)
        router.setRouteThrottle(workflowIdA, 1800, 500);

        // Prime market1 with initial value and market2 with a recent publish.
        {
            string[] memory refIds = new string[](2);
            bytes[] memory newValues = new bytes[](2);
            string[] memory updateTypes = new string[](2);
            address[] memory markets = new address[](2);
            bytes[] memory additionalData = new bytes[](2);
            refIds[0] = "r0";
            refIds[1] = "r1";
            newValues[0] = abi.encode(uint256(1e18)); // market1 initial value
            newValues[1] = abi.encode(uint256(1e18)); // market2 initial value
            updateTypes[0] = TYPE_DR;
            updateTypes[1] = TYPE_DR;
            markets[0] = market1;
            markets[1] = market2;
            additionalData[0] = bytes("");
            additionalData[1] = bytes("");
            bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);
            vm.prank(forwarder);
            router.onReport(metadata, abi.encode(refIds, newValues, updateTypes, markets, additionalData));
        }
        assertEq(sinkA.callCount(), 1);

        // Warp past min-delay so market2 would pass min-delay but market1 tries to jump 50% (fails max-step).
        vm.warp(block.timestamp + 2 hours);

        // Bulk: market1 with 50% increase (fails max-step), market2 with same value (would pass).
        string[] memory refIds2 = new string[](2);
        bytes[] memory newValues2 = new bytes[](2);
        string[] memory updateTypes2 = new string[](2);
        address[] memory markets2 = new address[](2);
        bytes[] memory additionalData2 = new bytes[](2);
        refIds2[0] = "r2";
        refIds2[1] = "r3";
        newValues2[0] = abi.encode(uint256(1.5e18)); // 50% increase, exceeds 5% max-step
        newValues2[1] = abi.encode(uint256(1e18)); // Same value, within bounds
        updateTypes2[0] = TYPE_DR;
        updateTypes2[1] = TYPE_DR;
        markets2[0] = market1; // Will fail max-step
        markets2[1] = market2; // Would pass
        additionalData2[0] = bytes("");
        additionalData2[1] = bytes("");

        // Expect revert when market1 (first element) fails max-step check.
        vm.expectRevert(
            abi.encodeWithSelector(
                LlamaguardRiskOracleRouter.ThrottleCheckFailed.selector, workflowIdA, market1, TYPE_DR
            )
        );
        vm.prank(forwarder);
        router.onReport(
            _buildMetadata(workflowIdA, workflowName, author),
            abi.encode(refIds2, newValues2, updateTypes2, markets2, additionalData2)
        );

        // No additional publish landed.
        assertEq(sinkA.callCount(), 1);

        // market2's record must NOT have been updated (transaction reverted).
        LlamaguardRiskOracleRouter.UpdateRecord memory rec2 = router.getUpdateRecord(workflowIdA, market2, TYPE_DR);
        // rec2.lastAt should still be from the priming call (block.timestamp - 2 hours), not from this failed batch.
        assertEq(rec2.lastAt, uint64(block.timestamp - 2 hours), "market2 timestamp should be unchanged from priming");
    }

    // ============================================================================================
    // Throttle — disabled state preserves legacy behavior
    // ============================================================================================

    function test_onReport_disabledThrottle_preservesLegacyBehavior() public {
        // Identical to test_onReport_happyPath_publishesAndDrivesAgentHub but with throttle
        // explicitly set to guard-off — confirms a default route is unaffected by the new code paths.
        _seedRouteA(address(hub));
        _programHubHappyPath();
        vm.prank(updater);
        router.setRouteThrottle(workflowIdA, 0, type(uint64).max); // MAX_STEP_OFF

        bytes memory report = abi.encode(uint256(123), uint256(456));
        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);
        vm.prank(forwarder);
        router.onReport(metadata, report);

        assertEq(sinkA.callCount(), 1);
        assertEq(hub.executeCallCount(), 1);
    }

    function test_onReport_maxStepOff_skipsDecodeEntirely() public {
        // When maxStepBps = MAX_STEP_OFF, no decode, no compare, lastValue not recorded.
        _seedThrottledSingleRoute(workflowIdA, address(sinkA));
        vm.prank(updater);
        router.setRouteThrottle(workflowIdA, 0, type(uint64).max);

        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);

        // Back-to-back publishes with huge delta should both succeed
        vm.prank(forwarder);
        router.onReport(metadata, _singleReport("r1", 1e18, TYPE_DR, market1));
        vm.prank(forwarder);
        router.onReport(metadata, _singleReport("r2", 1000e18, TYPE_DR, market1)); // 100000% jump
        assertEq(sinkA.callCount(), 2);

        // lastValue should NOT be recorded when guard is off
        LlamaguardRiskOracleRouter.UpdateRecord memory rec = router.getUpdateRecord(workflowIdA, market1, TYPE_DR);
        assertEq(rec.lastValue, 0, "lastValue should be 0 when MAX_STEP_OFF");
        assertFalse(rec.hasBaseline, "hasBaseline should be false when MAX_STEP_OFF");
        // lastAt is also not recorded when both guards are off (decode skipped entirely)
        assertEq(rec.lastAt, 0, "lastAt should be 0 when both guards off");
    }

    function test_onReport_frozen_rejectsChangeButPassesSameValue() public {
        // When maxStepBps = 0 (frozen), any value change is rejected but same-value republish passes.
        _seedThrottledSingleRoute(workflowIdA, address(sinkA));
        vm.prank(updater);
        router.setRouteThrottle(workflowIdA, 0, 0); // frozen

        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);

        // First publish (warm-up): always passes and records baseline
        vm.prank(forwarder);
        router.onReport(metadata, _singleReport("r1", 1e18, TYPE_DR, market1));
        assertEq(sinkA.callCount(), 1);

        // Second publish with different value: reverts
        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(
                LlamaguardRiskOracleRouter.ThrottleCheckFailed.selector, workflowIdA, market1, TYPE_DR
            )
        );
        router.onReport(metadata, _singleReport("r2", 1e18 + 1, TYPE_DR, market1));
        assertEq(sinkA.callCount(), 1);

        // Same value republish: passes
        vm.prank(forwarder);
        router.onReport(metadata, _singleReport("r3", 1e18, TYPE_DR, market1));
        assertEq(sinkA.callCount(), 2);
    }

    function test_onReport_frozen_warmupRecordsBaseline() public {
        // First publish (warm-up) always passes even when frozen, and records baseline.
        _seedThrottledSingleRoute(workflowIdA, address(sinkA));
        vm.prank(updater);
        router.setRouteThrottle(workflowIdA, 0, 0); // frozen

        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);

        // Before first publish: hasBaseline should be false
        LlamaguardRiskOracleRouter.UpdateRecord memory recBefore = router.getUpdateRecord(workflowIdA, market1, TYPE_DR);
        assertFalse(recBefore.hasBaseline, "hasBaseline should be false before first publish");

        vm.prank(forwarder);
        router.onReport(metadata, _singleReport("r1", 1e18, TYPE_DR, market1));
        assertEq(sinkA.callCount(), 1);

        LlamaguardRiskOracleRouter.UpdateRecord memory rec = router.getUpdateRecord(workflowIdA, market1, TYPE_DR);
        assertEq(rec.lastValue, 1e18, "baseline should be recorded on warm-up");
        assertEq(rec.lastAt, uint64(block.timestamp), "lastAt should be recorded");
        assertTrue(rec.hasBaseline, "hasBaseline should be true after first publish");
    }

    function test_onReport_frozen_tuplePayloadUnaffected() public {
        // Setting maxStepBps = 0 on a tuple-payload route does NOT freeze it.
        // The delta check only applies to 32-byte scalars.
        _seedThrottledSingleRoute(workflowIdA, address(sinkA));
        vm.prank(updater);
        router.setRouteThrottle(workflowIdA, 0, 0); // frozen

        // Tuple-shaped newValue (3 uint256s) — bypasses max-step entirely.
        bytes memory tupleValue1 = abi.encode(uint256(1), uint256(2), uint256(3));
        bytes memory tupleValue2 = abi.encode(uint256(100), uint256(200), uint256(300));
        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);

        vm.prank(forwarder);
        router.onReport(metadata, _singleReportRaw("r1", tupleValue1, TYPE_DR, market1));
        assertEq(sinkA.callCount(), 1);

        // Second publish with completely different tuple: should pass (delta check skipped for tuples)
        vm.prank(forwarder);
        router.onReport(metadata, _singleReportRaw("r2", tupleValue2, TYPE_DR, market1));
        assertEq(sinkA.callCount(), 2);

        // lastValue stayed 0 (non-scalar shape)
        LlamaguardRiskOracleRouter.UpdateRecord memory rec = router.getUpdateRecord(workflowIdA, market1, TYPE_DR);
        assertEq(rec.lastValue, 0, "tuple payloads don't record lastValue");
    }

    function test_onReport_frozen_zeroValueBaselineStaysFrozen() public {
        // Regression test: publishing a legitimate zero value should NOT un-freeze the route.
        // After publishing 0, a subsequent publish with a different value must still be rejected.
        _seedThrottledSingleRoute(workflowIdA, address(sinkA));
        vm.prank(updater);
        router.setRouteThrottle(workflowIdA, 0, 0); // frozen

        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);

        // First publish: value = 0 (legitimate zero, e.g., 0% rate)
        vm.prank(forwarder);
        router.onReport(metadata, _singleReport("r1", 0, TYPE_DR, market1));
        assertEq(sinkA.callCount(), 1);

        // Verify baseline is recorded
        LlamaguardRiskOracleRouter.UpdateRecord memory rec = router.getUpdateRecord(workflowIdA, market1, TYPE_DR);
        assertEq(rec.lastValue, 0, "baseline should be 0");
        assertTrue(rec.hasBaseline, "hasBaseline should be true after first publish");

        // Second publish with different value: must REVERT (route is frozen, not warm-up)
        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(
                LlamaguardRiskOracleRouter.ThrottleCheckFailed.selector, workflowIdA, market1, TYPE_DR
            )
        );
        router.onReport(metadata, _singleReport("r2", 999_999e18, TYPE_DR, market1));
        assertEq(sinkA.callCount(), 1, "frozen route should reject value change after zero baseline");

        // Same value (0) republish: should pass
        vm.prank(forwarder);
        router.onReport(metadata, _singleReport("r3", 0, TYPE_DR, market1));
        assertEq(sinkA.callCount(), 2, "same-value republish should pass");
    }

    function test_setRouteThrottle_acceptsMaxStepOff() public {
        _seedThrottledSingleRoute(workflowIdA, address(sinkA));
        vm.prank(updater);
        router.setRouteThrottle(workflowIdA, 0, type(uint64).max);

        (,,,, uint64 minDelay, uint64 maxStep,) = router.routes(workflowIdA);
        assertEq(maxStep, type(uint64).max);
        assertEq(minDelay, 0);
    }

    function test_setRouteThrottle_rejectsInvalidRange() public {
        _seedThrottledSingleRoute(workflowIdA, address(sinkA));

        // MAX_BPS + 1 is invalid
        vm.prank(updater);
        vm.expectRevert(abi.encodeWithSelector(LlamaguardRiskOracleRouter.BpsTooHigh.selector, uint64(10_001)));
        router.setRouteThrottle(workflowIdA, 0, 10_001);

        // type(uint64).max - 1 is also invalid
        vm.prank(updater);
        vm.expectRevert(abi.encodeWithSelector(LlamaguardRiskOracleRouter.BpsTooHigh.selector, type(uint64).max - 1));
        router.setRouteThrottle(workflowIdA, 0, type(uint64).max - 1);

        // MAX_STEP_OFF (type(uint64).max) is valid
        vm.prank(updater);
        router.setRouteThrottle(workflowIdA, 0, type(uint64).max);
        (,,,, uint64 minDelay, uint64 maxStep,) = router.routes(workflowIdA);
        assertEq(maxStep, type(uint64).max);
    }

    function test_onReport_defaultRoute_isFrozenAfterFirstPublish() public {
        // A freshly registered route has default throttle (0, 0) which means
        // (no min-delay, frozen max-step). After first publish, subsequent
        // value-changing publishes are rejected.
        _seedThrottledSingleRoute(workflowIdA, address(sinkA));
        // Don't call setRouteThrottle — use default (0, 0)

        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);

        // First publish (warm-up): passes
        vm.prank(forwarder);
        router.onReport(metadata, _singleReport("r1", 1e18, TYPE_DR, market1));
        assertEq(sinkA.callCount(), 1);

        // Second publish with different value: frozen, reverts
        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(
                LlamaguardRiskOracleRouter.ThrottleCheckFailed.selector, workflowIdA, market1, TYPE_DR
            )
        );
        router.onReport(metadata, _singleReport("r2", 2e18, TYPE_DR, market1));
        assertEq(sinkA.callCount(), 1);
    }

    function test_onReport_capped_zeroValueBaseline_rejectsNonZero() public {
        // Edge case: When baseline is 0 and maxStepBps is a relative cap (not frozen),
        // the formula `diff * MAX_BPS <= maxStepBps * last` becomes `diff * 10000 <= cap * 0 = 0`.
        // This means any non-zero value fails — mathematically correct (infinite % change from 0).
        _seedThrottledSingleRoute(workflowIdA, address(sinkA));
        vm.prank(updater);
        router.setRouteThrottle(workflowIdA, 0, 500); // 5% cap

        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);

        // First publish: value = 0 (warm-up passes, baseline recorded)
        vm.prank(forwarder);
        router.onReport(metadata, _singleReport("r1", 0, TYPE_DR, market1));
        assertEq(sinkA.callCount(), 1);

        LlamaguardRiskOracleRouter.UpdateRecord memory rec = router.getUpdateRecord(workflowIdA, market1, TYPE_DR);
        assertTrue(rec.hasBaseline, "hasBaseline should be true");
        assertEq(rec.lastValue, 0, "baseline should be 0");

        // Second publish with non-zero value: reverts (any delta from 0 is infinite %)
        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(
                LlamaguardRiskOracleRouter.ThrottleCheckFailed.selector, workflowIdA, market1, TYPE_DR
            )
        );
        router.onReport(metadata, _singleReport("r2", 1, TYPE_DR, market1)); // even 1 wei fails
        assertEq(sinkA.callCount(), 1);

        // Same value (0) republish: passes
        vm.prank(forwarder);
        router.onReport(metadata, _singleReport("r3", 0, TYPE_DR, market1));
        assertEq(sinkA.callCount(), 2);
    }

    function test_onReport_capped_boundaryExactlyAtCap_passes() public {
        // Boundary test: delta exactly at maxStepBps should pass.
        _seedThrottledSingleRoute(workflowIdA, address(sinkA));
        vm.prank(updater);
        router.setRouteThrottle(workflowIdA, 0, 1000); // 10% cap

        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);

        // Baseline: 1e18
        vm.prank(forwarder);
        router.onReport(metadata, _singleReport("r1", 1e18, TYPE_DR, market1));
        assertEq(sinkA.callCount(), 1);

        // Exactly +10%: 1.1e18 → diff = 0.1e18
        // Check: 0.1e18 * 10000 <= 1000 * 1e18 → 1e21 <= 1e21 ✓
        vm.prank(forwarder);
        router.onReport(metadata, _singleReport("r2", 11e17, TYPE_DR, market1));
        assertEq(sinkA.callCount(), 2, "exactly at cap should pass");

        // Now baseline is 1.1e18. Try +10% + 1 wei: should fail
        // 1.1e18 * 1.10 = 1.21e18, so 1.21e18 + 1 should fail
        uint256 baseline = 11e17;
        uint256 exactlyOver = baseline + (baseline * 1000 / 10_000) + 1; // 1.21e18 + 1
        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(
                LlamaguardRiskOracleRouter.ThrottleCheckFailed.selector, workflowIdA, market1, TYPE_DR
            )
        );
        router.onReport(metadata, _singleReport("r3", exactlyOver, TYPE_DR, market1));
        assertEq(sinkA.callCount(), 2);
    }

    function test_onReport_hasBaseline_survivesThrottleReconfiguration() public {
        // Verify hasBaseline persists when throttle settings are changed.
        _seedThrottledSingleRoute(workflowIdA, address(sinkA));
        vm.prank(updater);
        router.setRouteThrottle(workflowIdA, 0, 500); // 5% cap

        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);

        // Publish to establish baseline
        vm.prank(forwarder);
        router.onReport(metadata, _singleReport("r1", 1e18, TYPE_DR, market1));
        assertEq(sinkA.callCount(), 1);

        LlamaguardRiskOracleRouter.UpdateRecord memory recBefore = router.getUpdateRecord(workflowIdA, market1, TYPE_DR);
        assertTrue(recBefore.hasBaseline, "hasBaseline should be true");
        assertEq(recBefore.lastValue, 1e18);

        // Change throttle settings
        vm.prank(updater);
        router.setRouteThrottle(workflowIdA, 3600, 1000); // different delay and cap

        // hasBaseline should still be true
        LlamaguardRiskOracleRouter.UpdateRecord memory recAfter = router.getUpdateRecord(workflowIdA, market1, TYPE_DR);
        assertTrue(recAfter.hasBaseline, "hasBaseline should survive throttle reconfiguration");
        assertEq(recAfter.lastValue, 1e18, "lastValue should survive throttle reconfiguration");

        // Verify guard still applies (not warm-up): large delta should fail with new 10% cap
        vm.warp(block.timestamp + 3601); // past min-delay
        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(
                LlamaguardRiskOracleRouter.ThrottleCheckFailed.selector, workflowIdA, market1, TYPE_DR
            )
        );
        router.onReport(metadata, _singleReport("r2", 2e18, TYPE_DR, market1)); // +100% exceeds 10% cap
    }

    function test_onReport_maxStepOffToFrozen_firstPublishIsStillWarmup() public {
        // When a route transitions from MAX_STEP_OFF (no baseline recorded) to frozen,
        // the first publish should still be a warm-up (hasBaseline = false).
        _seedThrottledSingleRoute(workflowIdA, address(sinkA));
        vm.prank(updater);
        router.setRouteThrottle(workflowIdA, 0, type(uint64).max); // MAX_STEP_OFF

        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);

        // Publish with MAX_STEP_OFF — no baseline recorded
        vm.prank(forwarder);
        router.onReport(metadata, _singleReport("r1", 1e18, TYPE_DR, market1));
        assertEq(sinkA.callCount(), 1);

        LlamaguardRiskOracleRouter.UpdateRecord memory recOff = router.getUpdateRecord(workflowIdA, market1, TYPE_DR);
        assertFalse(recOff.hasBaseline, "hasBaseline should be false with MAX_STEP_OFF");
        assertEq(recOff.lastValue, 0, "lastValue should be 0 with MAX_STEP_OFF");

        // Now switch to frozen
        vm.prank(updater);
        router.setRouteThrottle(workflowIdA, 0, 0); // frozen

        // First publish after switch: should be warm-up (hasBaseline still false)
        vm.prank(forwarder);
        router.onReport(metadata, _singleReport("r2", 999e18, TYPE_DR, market1)); // huge value, but warm-up
        assertEq(sinkA.callCount(), 2, "first publish after switch should pass as warm-up");

        // Now hasBaseline should be true
        LlamaguardRiskOracleRouter.UpdateRecord memory recFrozen = router.getUpdateRecord(workflowIdA, market1, TYPE_DR);
        assertTrue(recFrozen.hasBaseline, "hasBaseline should be true after frozen warm-up");
        assertEq(recFrozen.lastValue, 999e18, "lastValue should be recorded");

        // Subsequent different value: frozen, should fail
        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(
                LlamaguardRiskOracleRouter.ThrottleCheckFailed.selector, workflowIdA, market1, TYPE_DR
            )
        );
        router.onReport(metadata, _singleReport("r3", 1e18, TYPE_DR, market1));
    }

    function test_onReport_maxBpsCap_allowsDoubling() public {
        // When maxStepBps = MAX_BPS (10000 = 100%), any delta up to 100% should pass.
        // This means value can double or halve in a single publish.
        _seedThrottledSingleRoute(workflowIdA, address(sinkA));
        vm.prank(updater);
        router.setRouteThrottle(workflowIdA, 0, 10_000); // 100% cap

        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);

        // Baseline: 1e18
        vm.prank(forwarder);
        router.onReport(metadata, _singleReport("r1", 1e18, TYPE_DR, market1));
        assertEq(sinkA.callCount(), 1);

        // Double (+100%): should pass
        vm.prank(forwarder);
        router.onReport(metadata, _singleReport("r2", 2e18, TYPE_DR, market1));
        assertEq(sinkA.callCount(), 2, "+100% should pass with 100% cap");

        // Halve (-50% from 2e18): should pass (50% < 100%)
        vm.prank(forwarder);
        router.onReport(metadata, _singleReport("r3", 1e18, TYPE_DR, market1));
        assertEq(sinkA.callCount(), 3, "-50% should pass with 100% cap");

        // More than double (+101%): should fail
        // From 1e18, +101% = 2.01e18
        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(
                LlamaguardRiskOracleRouter.ThrottleCheckFailed.selector, workflowIdA, market1, TYPE_DR
            )
        );
        router.onReport(metadata, _singleReport("r4", 201e16, TYPE_DR, market1)); // 2.01e18
        assertEq(sinkA.callCount(), 3);
    }

    function test_onReport_unknownSelector_throttlePassthrough() public {
        // A route using a non-IRiskOracle selector with throttle enabled should still
        // publish (decode is skipped, no guard applies). Documented behavior.
        _seedRouteA(address(0)); // uses mock `selectorA`, not canonical
        vm.prank(updater);
        router.setRouteThrottle(workflowIdA, 1800, 100);

        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);
        vm.prank(forwarder);
        router.onReport(metadata, hex"deadbeef");
        vm.prank(forwarder);
        router.onReport(metadata, hex"deadbeef"); // back-to-back, would trip if guard applied
        assertEq(sinkA.callCount(), 2);
    }

    // ============================================================================================
    // Throttle — record rollback when publish reverts after a passing guard
    // ============================================================================================

    function test_onReport_throttle_recordRolledBackWhenPublishReverts() public {
        _seedThrottledSingleRoute(workflowIdA, address(sinkA));
        vm.prank(updater);
        router.setRouteThrottle(workflowIdA, 1800, 0);

        // Force the sink to revert.
        sinkA.setShouldRevert(true, "boom");

        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);
        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(LlamaguardRiskOracleRouter.PublishFailed.selector, workflowIdA, bytes("boom"))
        );
        router.onReport(metadata, _singleReport("r1", 1e18, TYPE_DR, market1));

        // Record must be unmutated (whole tx reverted).
        LlamaguardRiskOracleRouter.UpdateRecord memory rec = router.getUpdateRecord(workflowIdA, market1, TYPE_DR);
        assertEq(rec.lastAt, 0);
        assertEq(rec.lastValue, 0);

        // Re-enable the sink; a subsequent publish lands without being blocked by stale record.
        sinkA.setShouldRevert(false, "");
        vm.prank(forwarder);
        router.onReport(metadata, _singleReport("r1", 1e18, TYPE_DR, market1));
        assertEq(sinkA.callCount(), 1);
    }

    // ============================================================================================
    // Replay guard — maxReportAgeSeconds (expiry + signed-timestamp ordering)
    // ============================================================================================

    uint64 internal constant REPORT_AGE = 1800;
    uint64 internal constant T0 = 1_700_000_000;

    function _envelope(uint64 signedAt, bytes memory payload) internal pure returns (bytes memory) {
        return abi.encode(signedAt, payload);
    }

    function _seedReplayGuardedSingleRoute() internal {
        _seedThrottledSingleRoute(workflowIdA, address(sinkA));
        vm.prank(updater);
        router.setRouteMaxReportAge(workflowIdA, REPORT_AGE);
        vm.warp(T0);
    }

    function test_setRouteMaxReportAge_onlyUpdater() public {
        _seedThrottledSingleRoute(workflowIdA, address(sinkA));
        vm.prank(rando);
        vm.expectRevert(LlamaguardRiskOracleRouter.OnlyUpdater.selector);
        router.setRouteMaxReportAge(workflowIdA, REPORT_AGE);
    }

    function test_setRouteMaxReportAge_revertsOnUnknownRoute() public {
        vm.prank(updater);
        vm.expectRevert(abi.encodeWithSelector(LlamaguardRiskOracleRouter.RouteNotFound.selector, workflowIdA));
        router.setRouteMaxReportAge(workflowIdA, REPORT_AGE);
    }

    /// @dev Zero is not "guard off" on a live route: the enveloping workflow wraps
    ///      unconditionally, so zero here silently changes the expected wire format and stops
    ///      every subsequent publish. The setter refuses it rather than bricking the route.
    function test_setRouteMaxReportAge_revertsOnZero() public {
        _seedReplayGuardedSingleRoute();
        vm.prank(updater);
        vm.expectRevert(abi.encodeWithSelector(LlamaguardRiskOracleRouter.InvalidReportAge.selector, uint64(0)));
        router.setRouteMaxReportAge(workflowIdA, 0);

        // The guard is untouched, so the route still publishes.
        (,,,,,, uint64 maxReportAge) = router.routes(workflowIdA);
        assertEq(maxReportAge, REPORT_AGE);
    }

    function test_setRouteMaxReportAge_revertsBelowMinimum() public {
        _seedThrottledSingleRoute(workflowIdA, address(sinkA));
        uint64 tooLow = router.MIN_REPORT_AGE_SECONDS() - 1;
        vm.prank(updater);
        vm.expectRevert(abi.encodeWithSelector(LlamaguardRiskOracleRouter.InvalidReportAge.selector, tooLow));
        router.setRouteMaxReportAge(workflowIdA, tooLow);
    }

    function test_setRouteMaxReportAge_acceptsExactMinimum() public {
        _seedThrottledSingleRoute(workflowIdA, address(sinkA));
        uint64 minAge = router.MIN_REPORT_AGE_SECONDS();
        vm.prank(updater);
        router.setRouteMaxReportAge(workflowIdA, minAge);

        (,,,,,, uint64 maxReportAge) = router.routes(workflowIdA);
        assertEq(maxReportAge, minAge);
    }

    function test_addRoute_registersGuardedRouteInOneCall() public {
        vm.prank(owner);
        router.addRoute({
            workflowId: workflowIdA,
            forwarder: forwarder,
            author: author,
            workflowName: workflowName,
            riskOracle: address(sinkA),
            publishSelector: selectorA,
            agentHub: address(0),
            agentIds: new uint256[](0),
            maxReportAgeSeconds: REPORT_AGE
        });

        (,,,,,, uint64 maxReportAge) = router.routes(workflowIdA);
        assertEq(maxReportAge, REPORT_AGE);

        // The route is immediately usable with the envelope, with no updater follow-up.
        vm.warp(T0);
        vm.prank(forwarder);
        router.onReport(
            _buildMetadata(workflowIdA, workflowName, author),
            _envelope(T0, _singleReport("r1", 1e18, TYPE_DR, market1))
        );
        assertEq(sinkA.callCount(), 1);
    }

    function test_addRoute_revertsOnReportAgeBelowMinimum() public {
        uint64 tooLow = router.MIN_REPORT_AGE_SECONDS() - 1;
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(LlamaguardRiskOracleRouter.InvalidReportAge.selector, tooLow));
        router.addRoute(
            workflowIdA,
            forwarder,
            author,
            workflowName,
            address(sinkA),
            selectorA,
            address(0),
            new uint256[](0),
            tooLow
        );
    }

    function test_setRouteMaxReportAge_emitsEventAndStoresValue() public {
        _seedThrottledSingleRoute(workflowIdA, address(sinkA));

        vm.recordLogs();
        vm.prank(updater);
        router.setRouteMaxReportAge(workflowIdA, REPORT_AGE);

        (,,,,,, uint64 maxReportAge) = router.routes(workflowIdA);
        assertEq(maxReportAge, REPORT_AGE);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256("RouteMaxReportAgeSet(bytes32,uint64)");
        bool found;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] == topic && logs[i].topics[1] == workflowIdA) {
                assertEq(abi.decode(logs[i].data, (uint64)), REPORT_AGE);
                found = true;
            }
        }
        assertTrue(found, "RouteMaxReportAgeSet not emitted");
    }

    function test_addRoute_replayGuardStartsOff() public {
        _seedThrottledSingleRoute(workflowIdA, address(sinkA));
        (,,,,,, uint64 maxReportAge) = router.routes(workflowIdA);
        assertEq(maxReportAge, 0);
    }

    function test_onReport_replayGuard_happyPath_forwardsInnerPayload() public {
        _seedReplayGuardedSingleRoute();

        bytes memory inner = _singleReport("r1", 1e18, TYPE_DR, market1);
        vm.prank(forwarder);
        router.onReport(_buildMetadata(workflowIdA, workflowName, author), _envelope(T0, inner));

        assertEq(sinkA.callCount(), 1);
        // The envelope must be stripped: the sink receives selector + bare RiskOracle payload.
        assertEq(sinkA.lastCalldata(), abi.encodePacked(RouterSelectors.PUBLISH_SINGLE_SELECTOR, inner));

        LlamaguardRiskOracleRouter.UpdateRecord memory rec = router.getUpdateRecord(workflowIdA, market1, TYPE_DR);
        assertEq(rec.lastSignedAt, T0);
    }

    function test_onReport_replayGuard_replaySameReport_reverts() public {
        _seedReplayGuardedSingleRoute();

        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);
        bytes memory report = _envelope(T0, _singleReport("r1", 1e18, TYPE_DR, market1));
        vm.prank(forwarder);
        router.onReport(metadata, report);

        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(
                LlamaguardRiskOracleRouter.OutOfOrderReport.selector, workflowIdA, market1, TYPE_DR, T0, T0
            )
        );
        router.onReport(metadata, report);
        assertEq(sinkA.callCount(), 1);
    }

    function test_onReport_replayGuard_olderReport_reverts() public {
        _seedReplayGuardedSingleRoute();

        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);
        vm.prank(forwarder);
        router.onReport(metadata, _envelope(T0, _singleReport("r1", 1e18, TYPE_DR, market1)));

        // A stale artifact signed before the last landed report cannot chain onto it.
        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(
                LlamaguardRiskOracleRouter.OutOfOrderReport.selector, workflowIdA, market1, TYPE_DR, T0 - 10, T0
            )
        );
        router.onReport(metadata, _envelope(T0 - 10, _singleReport("r0", 1e18, TYPE_DR, market1)));
    }

    function test_onReport_replayGuard_newerReport_passes() public {
        _seedReplayGuardedSingleRoute();

        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);
        vm.prank(forwarder);
        router.onReport(metadata, _envelope(T0, _singleReport("r1", 1e18, TYPE_DR, market1)));

        vm.warp(T0 + 60);
        vm.prank(forwarder);
        router.onReport(metadata, _envelope(T0 + 60, _singleReport("r2", 1e18, TYPE_DR, market1)));
        assertEq(sinkA.callCount(), 2);

        LlamaguardRiskOracleRouter.UpdateRecord memory rec = router.getUpdateRecord(workflowIdA, market1, TYPE_DR);
        assertEq(rec.lastSignedAt, T0 + 60);
    }

    function test_onReport_replayGuard_expiry_boundaryPassesThenReverts() public {
        _seedReplayGuardedSingleRoute();

        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);

        // Exactly at the age bound: passes (check is strict >).
        vm.warp(T0 + REPORT_AGE);
        vm.prank(forwarder);
        router.onReport(metadata, _envelope(T0, _singleReport("r1", 1e18, TYPE_DR, market1)));
        assertEq(sinkA.callCount(), 1);

        // One second past the bound: expired, even for a fresh key with no newer report.
        vm.warp(T0 + 2 * REPORT_AGE + 1);
        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(
                LlamaguardRiskOracleRouter.ReportExpired.selector, workflowIdA, T0 + REPORT_AGE, REPORT_AGE
            )
        );
        router.onReport(metadata, _envelope(T0 + REPORT_AGE, _singleReport("r2", 1e18, TYPE_DR, market2)));
    }

    function test_onReport_replayGuard_enforcedWhenThrottleFullyOff() public {
        _seedReplayGuardedSingleRoute();
        uint64 maxStepOff = router.MAX_STEP_OFF();
        vm.prank(updater);
        router.setRouteThrottle(workflowIdA, 0, maxStepOff);

        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);
        bytes memory report = _envelope(T0, _singleReport("r1", 1e18, TYPE_DR, market1));
        vm.prank(forwarder);
        router.onReport(metadata, report);

        // Ordering must trip even though min-delay and max-step are both off.
        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(
                LlamaguardRiskOracleRouter.OutOfOrderReport.selector, workflowIdA, market1, TYPE_DR, T0, T0
            )
        );
        router.onReport(metadata, report);
    }

    function test_onReport_replayGuard_bulk_recordsPerKey_andRejectsReplay() public {
        _seedThrottledBulkRoute(workflowIdA, address(sinkA));
        vm.prank(updater);
        router.setRouteMaxReportAge(workflowIdA, REPORT_AGE);
        vm.warp(T0);

        string[] memory refIds = new string[](2);
        bytes[] memory newValues = new bytes[](2);
        string[] memory updateTypes = new string[](2);
        address[] memory markets = new address[](2);
        bytes[] memory additionalData = new bytes[](2);
        refIds[0] = "r1";
        refIds[1] = "r2";
        newValues[0] = abi.encode(uint256(1e18));
        newValues[1] = abi.encode(uint256(2e18));
        updateTypes[0] = TYPE_DR;
        updateTypes[1] = TYPE_DR;
        markets[0] = market1;
        markets[1] = market2;
        additionalData[0] = bytes("");
        additionalData[1] = bytes("");

        bytes memory inner = abi.encode(refIds, newValues, updateTypes, markets, additionalData);
        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);
        vm.prank(forwarder);
        router.onReport(metadata, _envelope(T0, inner));

        assertEq(sinkA.callCount(), 1);
        assertEq(sinkA.lastCalldata(), abi.encodePacked(RouterSelectors.PUBLISH_BULK_SELECTOR, inner));
        assertEq(router.getUpdateRecord(workflowIdA, market1, TYPE_DR).lastSignedAt, T0);
        assertEq(router.getUpdateRecord(workflowIdA, market2, TYPE_DR).lastSignedAt, T0);

        // Replaying the whole batch trips on the first element.
        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(
                LlamaguardRiskOracleRouter.OutOfOrderReport.selector, workflowIdA, market1, TYPE_DR, T0, T0
            )
        );
        router.onReport(metadata, _envelope(T0, inner));
    }

    function test_onReport_replayGuard_recordRolledBackWhenPublishReverts() public {
        _seedReplayGuardedSingleRoute();
        sinkA.setShouldRevert(true, "boom");

        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);
        bytes memory report = _envelope(T0, _singleReport("r1", 1e18, TYPE_DR, market1));
        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(LlamaguardRiskOracleRouter.PublishFailed.selector, workflowIdA, bytes("boom"))
        );
        router.onReport(metadata, report);

        // lastSignedAt only persists for successful publishes: the failed attempt rolled back,
        // so the workflow's retry of the very same signed report must land.
        assertEq(router.getUpdateRecord(workflowIdA, market1, TYPE_DR).lastSignedAt, 0);
        sinkA.setShouldRevert(false, "");
        vm.prank(forwarder);
        router.onReport(metadata, report);
        assertEq(sinkA.callCount(), 1);
        assertEq(router.getUpdateRecord(workflowIdA, market1, TYPE_DR).lastSignedAt, T0);
    }

    function test_onReport_replayGuard_kickFailureStillRecords() public {
        vm.prank(owner);
        router.addRoute({
            workflowId: workflowIdA,
            forwarder: forwarder,
            author: author,
            workflowName: workflowName,
            riskOracle: address(sinkA),
            publishSelector: RouterSelectors.PUBLISH_SINGLE_SELECTOR,
            agentHub: address(hub),
            agentIds: _singletonAgentIds(7),
            maxReportAgeSeconds: 0
        });
        vm.prank(updater);
        router.setRouteMaxReportAge(workflowIdA, REPORT_AGE);
        vm.warp(T0);
        hub.setCheckShouldRevert(true, "hub down");

        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);
        vm.prank(forwarder);
        router.onReport(metadata, _envelope(T0, _singleReport("r1", 1e18, TYPE_DR, market1)));

        // The kick failure is caught after the publish; the record must not be skipped.
        assertEq(sinkA.callCount(), 1);
        assertEq(router.getUpdateRecord(workflowIdA, market1, TYPE_DR).lastSignedAt, T0);
    }

    // ============================================================================================
    // Guardian & Pause
    // ============================================================================================

    function test_setGuardian_onlyOwner() public {
        address guardian = makeAddr("guardian");
        vm.prank(rando);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, rando));
        router.setGuardian(guardian);

        vm.prank(owner);
        router.setGuardian(guardian);
        assertEq(router.guardian(), guardian);
    }

    function test_setGuardian_emitsGuardianSet() public {
        address guardian = makeAddr("guardian");

        vm.expectEmit(true, true, false, true);
        emit LlamaguardRiskOracleRouter.GuardianSet(address(0), guardian);

        vm.prank(owner);
        router.setGuardian(guardian);
    }

    function test_setGuardian_canSetToZero() public {
        address guardian = makeAddr("guardian");
        vm.prank(owner);
        router.setGuardian(guardian);
        assertEq(router.guardian(), guardian);

        vm.prank(owner);
        router.setGuardian(address(0));
        assertEq(router.guardian(), address(0));
    }

    function test_pause_ownerCanPause() public {
        vm.prank(owner);
        router.pause();
        assertTrue(router.paused());
    }

    function test_pause_guardianCanPause() public {
        address guardian = makeAddr("guardian");
        vm.prank(owner);
        router.setGuardian(guardian);

        vm.prank(guardian);
        router.pause();
        assertTrue(router.paused());
    }

    function test_pause_revertsForNonOwnerNonGuardian() public {
        vm.prank(rando);
        vm.expectRevert(LlamaguardRiskOracleRouter.NotOwnerOrGuardian.selector);
        router.pause();
    }

    function test_pause_updaterCannotPause() public {
        vm.prank(updater);
        vm.expectRevert(LlamaguardRiskOracleRouter.NotOwnerOrGuardian.selector);
        router.pause();
    }

    function test_unpause_onlyOwner() public {
        vm.prank(owner);
        router.pause();
        assertTrue(router.paused());

        vm.prank(rando);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, rando));
        router.unpause();

        vm.prank(owner);
        router.unpause();
        assertFalse(router.paused());
    }

    function test_unpause_guardianCannotUnpause() public {
        address guardian = makeAddr("guardian");
        vm.prank(owner);
        router.setGuardian(guardian);

        vm.prank(owner);
        router.pause();

        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, guardian));
        router.unpause();
    }

    function test_onReport_revertsWhenPaused() public {
        _seedRouteA(address(0));
        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);

        vm.prank(owner);
        router.pause();

        vm.prank(forwarder);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("EnforcedPause()"))));
        router.onReport(metadata, hex"deadbeef");
    }

    function test_onReport_succeedsAfterUnpause() public {
        _seedRouteA(address(0));
        bytes memory metadata = _buildMetadata(workflowIdA, workflowName, author);

        vm.prank(owner);
        router.pause();

        vm.prank(owner);
        router.unpause();

        vm.prank(forwarder);
        router.onReport(metadata, hex"deadbeef");
        assertEq(sinkA.callCount(), 1);
    }

    function test_constructor_startsUnpaused() public {
        LlamaguardRiskOracleRouter fresh = new LlamaguardRiskOracleRouter(owner);
        assertFalse(fresh.paused());
    }

    function test_constructor_guardianStartsZero() public {
        LlamaguardRiskOracleRouter fresh = new LlamaguardRiskOracleRouter(owner);
        assertEq(fresh.guardian(), address(0));
    }
}
