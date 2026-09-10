// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";
import { LlamaguardRiskOracleRouter } from "../../../src/LlamaguardRiskOracleRouter.sol";
import { RiskOracle } from "aave-v3-risk-stewards/contracts/dependencies/RiskOracle.sol";
import { RouterSelectors } from "../../../script/risk-oracles/RouterSelectors.sol";

/// @notice End-to-end test of the router against the canonical BGD `RiskOracle` from
///         `aave-v3-risk-stewards`. Catches the failure modes the byte-opaque mock can't:
///         (1) selector typo, (2) ABI shape mismatch between report payload and oracle
///         function signature, (3) authorised-sender ACL on the oracle, (4) unregistered
///         updateType allowlist on the oracle.
contract RouterRealRiskOracleTest is Test {
    LlamaguardRiskOracleRouter internal router;
    RiskOracle internal oracle;

    address internal owner = makeAddr("owner");
    address internal updater = makeAddr("updater");
    address internal forwarder = makeAddr("forwarder");
    address internal author = makeAddr("author");
    address internal market = makeAddr("ptToken-USDe");
    address internal market2 = makeAddr("ptToken-sUSDe");

    bytes32 internal workflowIdSingle = bytes32(uint256(0xA1));
    bytes32 internal workflowIdBulk = bytes32(uint256(0xB2));
    bytes10 internal workflowName = bytes10("pt_dr_v1__");

    // Stage 1 update-type strings the architecture pins.
    string internal constant TYPE_EMA = "EmaImpliedRateUpdate";
    string internal constant TYPE_DR = "PendleDiscountRateUpdate";
    string internal constant TYPE_EMODE = "EModeCategoryUpdate";

    function setUp() public virtual {
        router = new LlamaguardRiskOracleRouter(owner);

        // Deploy RiskOracle with the router pre-authorised + the three Stage 1 updateTypes.
        address[] memory initialSenders = new address[](1);
        initialSenders[0] = address(router);

        string[] memory initialUpdateTypes = new string[](3);
        initialUpdateTypes[0] = TYPE_EMA;
        initialUpdateTypes[1] = TYPE_DR;
        initialUpdateTypes[2] = TYPE_EMODE;

        oracle = new RiskOracle("LlamaRisk PT oracle (test)", initialSenders, initialUpdateTypes);

        vm.prank(owner);
        router.setUpdater(updater);

        _addRoute(workflowIdSingle, RouterSelectors.PUBLISH_SINGLE_SELECTOR);
        _addRoute(workflowIdBulk, RouterSelectors.PUBLISH_BULK_SELECTOR);
    }

    function _addRoute(bytes32 workflowId, bytes4 selector) internal {
        vm.prank(owner);
        router.addRoute({
            workflowId: workflowId,
            forwarder: forwarder,
            author: author,
            workflowName: workflowName,
            riskOracle: address(oracle),
            publishSelector: selector,
            agentHub: address(0), // no injection in these tests; just verify the publish leg
            agentIds: new uint256[](0),
            maxReportAgeSeconds: 0
        });
        // Set throttle to guard off (MAX_STEP_OFF) so updates with different values pass.
        // Individual tests can override this with setRouteThrottle if they need specific throttle behavior.
        // Cache MAX_STEP_OFF before prank to avoid the external call consuming the prank.
        uint64 maxStepOff = router.MAX_STEP_OFF();
        vm.prank(updater);
        router.setRouteThrottle(workflowId, 0, maxStepOff);
    }

    function _buildMetadata(bytes32 workflowId) internal view returns (bytes memory) {
        bytes memory out = new bytes(62);
        bytes10 name = workflowName;
        address authorAddr = author;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(add(out, 32), workflowId)
            mstore(add(out, 64), name)
            mstore(add(out, 74), shl(96, authorAddr))
        }
        return out;
    }

    // ============================================================================================
    // Happy path — single record
    // ============================================================================================

    /// @dev Proves the full pipeline: router validates CRE metadata, packs
    ///      `(selector || abi.encode(args))`, sinks into the real RiskOracle, which decodes,
    ///      authorises, allowlists the updateType, increments updateCounter, and persists.
    function test_routerWritesSingleDiscountRateUpdate() public {
        string memory refId = "round-42";
        bytes memory newValue = abi.encode(uint256(5e16)); // 5%/yr in 1e18
        bytes memory additionalData = abi.encode(uint256(4_900_000_000_000_000), uint32(1));

        bytes memory report = abi.encode(refId, newValue, TYPE_DR, market, additionalData);
        bytes memory metadata = _buildMetadata(workflowIdSingle);

        // Pre-state
        assertEq(oracle.updateCounter(), 0);

        vm.prank(forwarder);
        router.onReport(metadata, report);

        // Post-state — the oracle should hold exactly what we published.
        assertEq(oracle.updateCounter(), 1);

        RiskOracle.RiskParameterUpdate memory got = oracle.getLatestUpdateByParameterAndMarket(TYPE_DR, market);
        assertEq(got.referenceId, refId);
        assertEq(keccak256(got.newValue), keccak256(newValue));
        assertEq(got.updateType, TYPE_DR);
        assertEq(got.market, market);
        assertEq(keccak256(got.additionalData), keccak256(additionalData));
        assertEq(got.updateId, 1);
        assertEq(got.previousValue.length, 0); // first ever update for (TYPE_DR, market)
        assertEq(got.timestamp, block.timestamp);
    }

    /// @dev Second write should populate `previousValue` from the first write's `newValue`.
    function test_routerWritesTwoUpdates_previousValueChains() public {
        bytes memory firstValue = abi.encode(uint256(5e16));
        bytes memory secondValue = abi.encode(uint256(6e16));
        bytes memory metadata = _buildMetadata(workflowIdSingle);

        vm.prank(forwarder);
        router.onReport(metadata, abi.encode("r1", firstValue, TYPE_DR, market, bytes("")));

        vm.prank(forwarder);
        router.onReport(metadata, abi.encode("r2", secondValue, TYPE_DR, market, bytes("")));

        RiskOracle.RiskParameterUpdate memory got = oracle.getLatestUpdateByParameterAndMarket(TYPE_DR, market);
        assertEq(keccak256(got.newValue), keccak256(secondValue));
        assertEq(keccak256(got.previousValue), keccak256(firstValue));
        assertEq(got.updateId, 2);
        assertEq(oracle.updateCounter(), 2);
    }

    // ============================================================================================
    // Happy path — bulk
    // ============================================================================================

    /// @dev Proves the bulk variant's selector + parallel-arrays encoding round-trips. A real
    ///      risk-params batch publishes one record per (PT, eMode) reserve in a single tx.
    function test_routerWritesBulkEModeBatch() public {
        // Three records: same updateType + market repeated across distinct
        // additionalData blobs to mimic the (PT, eMode-category) fan-out.
        string[] memory refIds = new string[](3);
        bytes[] memory newValues = new bytes[](3);
        string[] memory updateTypes = new string[](3);
        address[] memory markets = new address[](3);
        bytes[] memory additionalData = new bytes[](3);

        refIds[0] = "emode-stables";
        refIds[1] = "emode-usde";
        refIds[2] = "emode-other-market";

        newValues[0] = abi.encode(uint256(78e16), uint256(76e16), uint256(5e16)); // (LTV, LT, LB) 1e18
        newValues[1] = abi.encode(uint256(80e16), uint256(78e16), uint256(5e16));
        newValues[2] = abi.encode(uint256(82e16), uint256(80e16), uint256(4e16));

        updateTypes[0] = TYPE_EMODE;
        updateTypes[1] = TYPE_EMODE;
        updateTypes[2] = TYPE_EMODE;

        markets[0] = market;
        markets[1] = market;
        markets[2] = market2;

        additionalData[0] = abi.encode(uint16(1)); // eModeCategoryId
        additionalData[1] = abi.encode(uint16(2));
        additionalData[2] = abi.encode(uint16(1));

        bytes memory report = abi.encode(refIds, newValues, updateTypes, markets, additionalData);
        bytes memory metadata = _buildMetadata(workflowIdBulk);

        vm.prank(forwarder);
        router.onReport(metadata, report);

        // All three records persisted with monotonic ids.
        assertEq(oracle.updateCounter(), 3);

        // (TYPE_EMODE, market) — latest is the 2nd record (id=2), previousValue chains from 1st.
        RiskOracle.RiskParameterUpdate memory marketLatest =
            oracle.getLatestUpdateByParameterAndMarket(TYPE_EMODE, market);
        assertEq(marketLatest.updateId, 2);
        assertEq(keccak256(marketLatest.newValue), keccak256(newValues[1]));
        assertEq(keccak256(marketLatest.previousValue), keccak256(newValues[0]));
        assertEq(keccak256(marketLatest.additionalData), keccak256(additionalData[1]));

        // (TYPE_EMODE, market2) — single record, no previous.
        RiskOracle.RiskParameterUpdate memory market2Latest =
            oracle.getLatestUpdateByParameterAndMarket(TYPE_EMODE, market2);
        assertEq(market2Latest.updateId, 3);
        assertEq(keccak256(market2Latest.newValue), keccak256(newValues[2]));
        assertEq(market2Latest.previousValue.length, 0);

        // Spot-check the by-id getter to confirm full traversal works.
        RiskOracle.RiskParameterUpdate memory firstById = oracle.getUpdateById(1);
        assertEq(firstById.referenceId, "emode-stables");
        assertEq(keccak256(firstById.newValue), keccak256(newValues[0]));
    }

    // ============================================================================================
    // Negative — unauthorised router
    // ============================================================================================

    /// @dev Removes the router from the oracle's authorised-sender set, then sends a report.
    ///      The oracle reverts with the `onlyAuthorized` modifier's reason string and the
    ///      router surfaces it via `PublishFailed`.
    function test_routerPublishReverts_whenNotAuthorisedOnOracle() public {
        // Owner of RiskOracle is this test contract (it deployed the oracle in setUp).
        oracle.removeAuthorizedSender(address(router));
        assertFalse(oracle.isAuthorized(address(router)));

        bytes memory report = abi.encode("r-x", abi.encode(uint256(1)), TYPE_DR, market, bytes(""));
        bytes memory metadata = _buildMetadata(workflowIdSingle);

        bytes memory expectedRevertData =
            abi.encodeWithSignature("Error(string)", "Unauthorized: Sender not authorized.");
        vm.expectRevert(
            abi.encodeWithSelector(
                LlamaguardRiskOracleRouter.PublishFailed.selector, workflowIdSingle, expectedRevertData
            )
        );
        vm.prank(forwarder);
        router.onReport(metadata, report);

        // Nothing should have landed.
        assertEq(oracle.updateCounter(), 0);
    }

    // ============================================================================================
    // Negative — unregistered updateType
    // ============================================================================================

    /// @dev RiskOracle keeps an allowlist of update types (set at construction; mutable via
    ///      `addUpdateType` by the oracle owner). Sending a non-allowlisted type should
    ///      revert at the oracle, bubble through `PublishFailed`, and leave the counter at 0.
    function test_routerPublishReverts_whenUpdateTypeNotRegistered() public {
        string memory bogusType = "NotARegisteredType";
        bytes memory report = abi.encode("r-x", abi.encode(uint256(1)), bogusType, market, bytes(""));
        bytes memory metadata = _buildMetadata(workflowIdSingle);

        bytes memory expectedRevertData = abi.encodeWithSignature("Error(string)", "Unauthorized update type.");
        vm.expectRevert(
            abi.encodeWithSelector(
                LlamaguardRiskOracleRouter.PublishFailed.selector, workflowIdSingle, expectedRevertData
            )
        );
        vm.prank(forwarder);
        router.onReport(metadata, report);

        assertEq(oracle.updateCounter(), 0);
    }

    // ============================================================================================
    // Throttle — end-to-end against the real RiskOracle
    // ============================================================================================

    /// @dev Confirms the router-side throttle short-circuits the real oracle: a second
    ///      publish within `minDelaySeconds` does NOT increment `updateCounter`, and after
    ///      warping past the delay window the publish lands as expected.
    function test_throttle_blocksRealOracleWriteAndPassesAfterDelay() public {
        vm.prank(updater);
        router.setRouteThrottle(workflowIdSingle, 1 hours, 0);

        bytes memory metadata = _buildMetadata(workflowIdSingle);

        vm.prank(forwarder);
        router.onReport(metadata, abi.encode("r1", abi.encode(uint256(5e16)), TYPE_DR, market, bytes("")));
        assertEq(oracle.updateCounter(), 1);

        // Second publish immediately — throttled, reverts.
        vm.expectRevert(
            abi.encodeWithSelector(
                LlamaguardRiskOracleRouter.ThrottleCheckFailed.selector, workflowIdSingle, market, TYPE_DR
            )
        );
        vm.prank(forwarder);
        router.onReport(metadata, abi.encode("r2", abi.encode(uint256(5e16)), TYPE_DR, market, bytes("")));
        assertEq(oracle.updateCounter(), 1);

        // Past the delay window — publish lands again.
        vm.warp(block.timestamp + 1 hours);
        vm.prank(forwarder);
        router.onReport(metadata, abi.encode("r3", abi.encode(uint256(5e16)), TYPE_DR, market, bytes("")));
        assertEq(oracle.updateCounter(), 2);
    }
}
