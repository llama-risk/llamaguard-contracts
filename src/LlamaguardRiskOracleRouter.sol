// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { Ownable, Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { AbstractRoutedCreReceiver } from "./abstracts/AbstractRoutedCreReceiver.sol";
import { IAgentHub } from "./interfaces/IAgentHub.sol";
import { IRiskOracle } from "aave-v3-risk-stewards/contracts/dependencies/IRiskOracle.sol";

/// @title LlamaguardRiskOracleRouter
/// @notice Multi-workflow CRE receiver that routes validated reports to the configured
///         downstream LlamaguardRiskOracle and atomically drives AgentHub injection via the
///         BGD `check` + `execute` pair.
/// @dev Multi-tenant successor to `contracts/lib/llamaguard-contracts/src/LlamaGuardOracleProxy.sol`.
///      Validation of `(forwarder, author, workflowName, isActive)` is inherited from
///      `AbstractRoutedCreReceiver.workflowConfigs`. This contract adds a parallel `routes` mapping
///      keyed by the same `workflowId` storing the downstream oracle target and the AgentHub
///      action set to invoke after a successful publish.
///
///      Atomic publish + injection semantics:
///      - publish revert → whole tx reverts (workflow retries)
///      - AgentHub kick revert → caught and emitted (oracle update lands; any subsequent
///        caller can re-run check+execute against the still-pending update)
///
///      Replay guard (per route, via `maxReportAgeSeconds`): when enabled the report is the
///      envelope `abi.encode(uint64 signedAt, bytes payload)` and the router enforces both a
///      report age bound (`ReportExpired`) and strict signed-timestamp ordering per
///      `(workflowId, market, updateType)` (`OutOfOrderReport`), closing replay of failed
///      signed reports retained by the KeystoneForwarder.
contract LlamaguardRiskOracleRouter is Ownable2Step, ReentrancyGuard, Pausable, AbstractRoutedCreReceiver {
    struct Route {
        address riskOracle; // downstream LlamaguardRiskOracle
        bytes4 publishSelector; // e.g. publishRiskParameterUpdate.selector
        address agentHub; // AgentHub to drive; zero = skip injection
        uint256[] agentIds; // agent IDs to feed into AgentHub.check()
        bool enabled;
        uint64 minDelaySeconds; // 0 = no min-delay
        uint64 maxStepBps; // MAX_STEP_OFF = off; 0 = frozen; 1..MAX_BPS = relative cap
        uint64 maxReportAgeSeconds; // 0 = replay guard off (bare report); nonzero = envelope required
    }

    /// @notice Per-(workflow, market, updateType) record used by the on-chain throttle.
    /// @dev Fields:
    ///      - `lastAt`: timestamp of the most recent publish (0 if never published)
    ///      - `hasBaseline`: true after the first 32-byte scalar publish; distinguishes
    ///        "never published" from "published a legitimate zero value" so that zero
    ///        is a valid baseline rather than a warm-up sentinel
    ///      - `lastSignedAt`: consensus timestamp signed into the most recent successfully
    ///        published enveloped report (0 if the route has never published with the replay
    ///        guard on); the replay ordering check rejects any report not strictly newer
    ///      - `lastValue`: the most recent 32-byte scalar value; only meaningful when
    ///        `hasBaseline == true`; zero is a valid stored value
    struct UpdateRecord {
        uint64 lastAt;
        bool hasBaseline;
        uint64 lastSignedAt;
        uint256 lastValue;
    }

    /// @dev Max-step cap that mirrors `PTParameterRegistry`'s `MAX_BPS`. Allows up to a
    ///      100% move.
    uint64 internal constant MAX_BPS = 10_000;

    /// @notice Sentinel value for disabling the max-step guard entirely. When `maxStepBps`
    ///         equals this value, the route skips decode, compare, and lastValue recording.
    ///         Use for routes where per-fire delta capping is not desired (e.g., EMA routes).
    uint64 public constant MAX_STEP_OFF = type(uint64).max;

    /// @notice Lower bound on a nonzero `maxReportAgeSeconds`. Any positive value below this
    ///         would expire every report before it could be delivered, bricking the route as
    ///         surely as a wire-format mismatch. `addRoute` still accepts an explicit `0`
    ///         (guard off, bare payload); `setRouteMaxReportAge` does not, because on a live
    ///         enveloping route "off" is not a relaxation, it is a hard stop.
    uint64 public constant MIN_REPORT_AGE_SECONDS = 60;

    /// @dev Canonical IRiskOracle selectors. The throttle guard decodes the report payload
    ///      only when the route's `publishSelector` matches one of these; routes wired to
    ///      anything else pass through with no guard (forward-compat with future write
    ///      shapes — the route operator should set maxStepBps to MAX_STEP_OFF there).
    bytes4 internal constant _PUBLISH_SINGLE_SELECTOR = IRiskOracle.publishRiskParameterUpdate.selector;
    bytes4 internal constant _PUBLISH_BULK_SELECTOR = IRiskOracle.publishBulkRiskParameterUpdates.selector;

    address public updater;
    address public guardian;
    mapping(bytes32 workflowId => Route) public routes;
    mapping(bytes32 workflowId => mapping(address market => mapping(bytes32 updateTypeHash => UpdateRecord))) private
        _records;

    event UpdaterChanged(address indexed previousUpdater, address indexed newUpdater);
    event GuardianSet(address indexed previousGuardian, address indexed newGuardian);
    event RouteAdded(
        bytes32 indexed workflowId,
        address forwarder,
        address author,
        bytes10 workflowName,
        address riskOracle,
        bytes4 publishSelector,
        address agentHub,
        uint256[] agentIds
    );
    event RouteRemoved(bytes32 indexed workflowId);
    event RouteEnabledSet(bytes32 indexed workflowId, bool enabled);
    event RouteRiskOracleSet(bytes32 indexed workflowId, address riskOracle, bytes4 publishSelector);
    event RouteAgentHubSet(bytes32 indexed workflowId, address agentHub);
    event RouteAgentIdsSet(bytes32 indexed workflowId, uint256[] agentIds);
    event RouteThrottleSet(bytes32 indexed workflowId, uint64 minDelaySeconds, uint64 maxStepBps);
    event RouteMaxReportAgeSet(bytes32 indexed workflowId, uint64 maxReportAgeSeconds);
    event ReportRouted(bytes32 indexed workflowId, address indexed riskOracle, bytes4 publishSelector);
    event AgentHubKickSkipped(bytes32 indexed workflowId, string reason);
    event AgentHubKickResultSuccess(bytes32 indexed workflowId);
    event AgentHubKickResultFailed(bytes32 indexed workflowId, bytes returnData);

    error OnlyUpdater();
    error ZeroAddress();
    error ZeroSelector();
    error ZeroWorkflowName();
    error EmptyAgentIds();
    error InvalidRiskOracle(address riskOracle);
    error RouteAlreadyExists(bytes32 workflowId);
    error RouteNotFound(bytes32 workflowId);
    error RouteDisabled(bytes32 workflowId);
    error PublishFailed(bytes32 workflowId, bytes returnData);
    error WorkflowConfigDesync(bytes32 workflowId);
    error BpsTooHigh(uint64 bps);
    error InvalidReportAge(uint64 maxReportAgeSeconds);
    error NotOwnerOrGuardian();
    error ThrottleCheckFailed(bytes32 workflowId, address market, string updateType);
    error ReportExpired(bytes32 workflowId, uint64 signedAt, uint64 maxReportAgeSeconds);
    error OutOfOrderReport(bytes32 workflowId, address market, string updateType, uint64 signedAt, uint64 lastSignedAt);

    modifier onlyUpdater() {
        if (msg.sender != updater) revert OnlyUpdater();
        _;
    }

    modifier onlyOwnerOrGuardian() {
        if (msg.sender != owner() && msg.sender != guardian) revert NotOwnerOrGuardian();
        _;
    }

    constructor(address owner_) Ownable(owner_) { }

    // ============================================================================================
    // Owner functions
    // ============================================================================================

    function setUpdater(address _updater) external onlyOwner {
        if (_updater == address(0)) revert ZeroAddress();
        address previous = updater;
        updater = _updater;
        emit UpdaterChanged(previous, _updater);
    }

    /// @notice Set the guardian address. The guardian can pause and unpause the router.
    function setGuardian(address _guardian) external onlyOwner {
        address previous = guardian;
        guardian = _guardian;
        emit GuardianSet(previous, _guardian);
    }

    function pause() external onlyOwnerOrGuardian {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Add a new route (and its CRE workflow config) in one call.
    /// @dev Reverts if a route is already configured for this workflowId. Use `setRiskOracle` /
    ///      `setAgentHub` / `setAgentIds` / `setRouteEnabled` to mutate.
    ///      When `agentHub == address(0)` the post-publish injection is skipped entirely and
    ///      `agentIds` is allowed (but ignored).
    ///
    ///      `maxReportAgeSeconds` picks the report wire format up front, so a route is never
    ///      live in a state its workflow cannot satisfy: `0` registers an unguarded route that
    ///      expects the bare RiskOracle payload, and any value `>= MIN_REPORT_AGE_SECONDS`
    ///      registers a guarded route that expects the `abi.encode(uint64 signedAt, bytes payload)`
    ///      envelope. Values in `1..MIN_REPORT_AGE_SECONDS-1` revert.
    function addRoute(
        bytes32 workflowId,
        address forwarder,
        address author,
        bytes10 workflowName,
        address riskOracle,
        bytes4 publishSelector,
        address agentHub,
        uint256[] calldata agentIds,
        uint64 maxReportAgeSeconds
    )
        external
        onlyOwner
    {
        if (!_isContract(riskOracle) || riskOracle == address(0)) revert InvalidRiskOracle(riskOracle);
        if (routes[workflowId].riskOracle != address(0)) revert RouteAlreadyExists(workflowId);
        if (publishSelector == bytes4(0)) revert ZeroSelector();
        if (forwarder == address(0)) revert ZeroAddress();
        if (author == address(0)) revert ZeroAddress();
        if (workflowName == bytes10(0)) revert ZeroWorkflowName();
        if (agentHub != address(0) && agentIds.length == 0) revert EmptyAgentIds();
        if (maxReportAgeSeconds != 0 && maxReportAgeSeconds < MIN_REPORT_AGE_SECONDS) {
            revert InvalidReportAge(maxReportAgeSeconds);
        }

        workflowConfigs[workflowId] = WorkflowConfig({
            expectedForwarder: forwarder, expectedAuthor: author, expectedWorkflowName: workflowName, isActive: true
        });

        routes[workflowId] = Route({
            riskOracle: riskOracle,
            publishSelector: publishSelector,
            agentHub: agentHub,
            agentIds: agentIds,
            enabled: true,
            minDelaySeconds: 0,
            maxStepBps: 0,
            maxReportAgeSeconds: maxReportAgeSeconds
        });

        emit WorkflowConfigUpdated(workflowId, forwarder, author, workflowName, true);
        emit RouteAdded(workflowId, forwarder, author, workflowName, riskOracle, publishSelector, agentHub, agentIds);
        emit RouteMaxReportAgeSet(workflowId, maxReportAgeSeconds);
    }

    function removeRoute(bytes32 workflowId) external onlyOwner {
        if (routes[workflowId].riskOracle == address(0)) revert RouteNotFound(workflowId);
        delete routes[workflowId];
        delete workflowConfigs[workflowId];
        emit RouteRemoved(workflowId);
        emit WorkflowConfigUpdated(workflowId, address(0), address(0), bytes10(0), false);
    }

    function setRiskOracle(bytes32 workflowId, address riskOracle, bytes4 publishSelector) external onlyOwner {
        if (routes[workflowId].riskOracle == address(0)) revert RouteNotFound(workflowId);
        if (!_isContract(riskOracle) || riskOracle == address(0)) revert InvalidRiskOracle(riskOracle);
        if (publishSelector == bytes4(0)) revert ZeroSelector();
        routes[workflowId].riskOracle = riskOracle;
        routes[workflowId].publishSelector = publishSelector;
        emit RouteRiskOracleSet(workflowId, riskOracle, publishSelector);
    }

    function setAgentHub(bytes32 workflowId, address agentHub) external onlyOwner {
        if (routes[workflowId].riskOracle == address(0)) revert RouteNotFound(workflowId);
        // Keep the invariant: if injection is enabled, an agentIds set must be configured.
        if (agentHub != address(0) && routes[workflowId].agentIds.length == 0) revert EmptyAgentIds();
        routes[workflowId].agentHub = agentHub;
        emit RouteAgentHubSet(workflowId, agentHub);
    }

    // ============================================================================================
    // Updater functions
    // ============================================================================================

    function setRouteEnabled(bytes32 workflowId, bool enabled_) external onlyUpdater {
        if (routes[workflowId].riskOracle == address(0)) revert RouteNotFound(workflowId);

        // Explicit invariant: addRoute / removeRoute always populate or clear both `routes` and
        // `workflowConfigs` together. If a future change ever splits those, this guard surfaces
        // the desync instead of silently writing into a half-initialised config slot.
        WorkflowConfig storage cfg = workflowConfigs[workflowId];
        if (cfg.expectedForwarder == address(0)) revert WorkflowConfigDesync(workflowId);

        routes[workflowId].enabled = enabled_;
        cfg.isActive = enabled_;

        emit RouteEnabledSet(workflowId, enabled_);
        emit WorkflowConfigUpdated(
            workflowId, cfg.expectedForwarder, cfg.expectedAuthor, cfg.expectedWorkflowName, enabled_
        );
    }

    function setAgentIds(bytes32 workflowId, uint256[] calldata agentIds) external onlyUpdater {
        if (routes[workflowId].riskOracle == address(0)) revert RouteNotFound(workflowId);
        // If injection is on, the agentIds set must be non-empty so `check()` has work.
        if (routes[workflowId].agentHub != address(0) && agentIds.length == 0) revert EmptyAgentIds();
        routes[workflowId].agentIds = agentIds;
        emit RouteAgentIdsSet(workflowId, agentIds);
    }

    /// @notice Tune the per-route on-chain throttle.
    /// @param minDelaySeconds Minimum elapsed time between publishes for the same
    ///        `(workflowId, market, updateType)`. Set `0` to disable.
    /// @param maxStepBps Maximum relative move vs the last published value (basis points).
    ///        Semantics:
    ///        - `MAX_STEP_OFF` (type(uint64).max): guard off — no decode, no compare, lastValue not recorded
    ///        - `0`: frozen — any value change rejected; same-value republish passes; warm-up records baseline
    ///        - `1..MAX_BPS`: relative cap — `|delta| / lastValue <= maxStepBps / 10000`
    ///        - `MAX_BPS+1..MAX_STEP_OFF-1`: invalid — setter reverts
    ///        Note: max-step only applies to 32-byte scalar payloads. Setting 0 on a tuple-payload
    ///        route does NOT freeze it (use `setRouteEnabled(false)` to freeze tuple routes).
    function setRouteThrottle(bytes32 workflowId, uint64 minDelaySeconds, uint64 maxStepBps) external onlyUpdater {
        if (routes[workflowId].riskOracle == address(0)) revert RouteNotFound(workflowId);
        if (maxStepBps > MAX_BPS && maxStepBps != MAX_STEP_OFF) revert BpsTooHigh(maxStepBps);
        routes[workflowId].minDelaySeconds = minDelaySeconds;
        routes[workflowId].maxStepBps = maxStepBps;
        emit RouteThrottleSet(workflowId, minDelaySeconds, maxStepBps);
    }

    /// @notice Tune the per-route replay guard (report expiry + ordering).
    /// @param maxReportAgeSeconds Maximum accepted age of a report's signed consensus timestamp.
    ///        Must be `>= MIN_REPORT_AGE_SECONDS`; anything lower reverts `InvalidReportAge`.
    ///        The report MUST be the envelope `abi.encode(uint64 signedAt, bytes payload)`; the
    ///        router rejects reports older than `maxReportAgeSeconds` (`ReportExpired`) and
    ///        reports whose `signedAt` is not strictly newer than the last successfully published
    ///        one for the same `(workflowId, market, updateType)` (`OutOfOrderReport`).
    ///        Size it above workflow execution + delivery latency and below the workflow's cron
    ///        interval.
    /// @dev Deliberately cannot set `0`. Because the enveloping workflow has no route lookup and
    ///      wraps unconditionally, `0` on a live guarded route is not "guard off", it is a
    ///      wire-format change that stops every subsequent publish. It reads like an incident
    ///      lever and behaves like a kill switch, so it is not reachable here. Registering an
    ///      unguarded route is an `addRoute(..., 0)` decision, and reverting a live route to the
    ///      bare wire format is deliberately an owner action (`removeRoute` + `addRoute`).
    ///      To stop a route without changing its wire format, use `setRouteEnabled(false)`.
    function setRouteMaxReportAge(bytes32 workflowId, uint64 maxReportAgeSeconds) external onlyUpdater {
        if (routes[workflowId].riskOracle == address(0)) revert RouteNotFound(workflowId);
        if (maxReportAgeSeconds < MIN_REPORT_AGE_SECONDS) revert InvalidReportAge(maxReportAgeSeconds);
        routes[workflowId].maxReportAgeSeconds = maxReportAgeSeconds;
        emit RouteMaxReportAgeSet(workflowId, maxReportAgeSeconds);
    }

    // ============================================================================================
    // Views
    // ============================================================================================

    /// @notice Returns the configured agent IDs for a workflow (the public mapping getter
    ///         omits dynamic arrays, so this view exists for off-chain consumers and tests).
    function getAgentIds(bytes32 workflowId) external view returns (uint256[] memory) {
        return routes[workflowId].agentIds;
    }

    /// @notice Returns the throttle record for a `(workflowId, market, updateType)` triple.
    ///         Used by ops/tests to observe when a route last published, whether a baseline
    ///         exists (`hasBaseline`), and the last 32-byte scalar value sampled by the
    ///         delta guard (`lastValue` — only meaningful when `hasBaseline == true`).
    function getUpdateRecord(
        bytes32 workflowId,
        address market,
        string calldata updateType
    )
        external
        view
        returns (UpdateRecord memory)
    {
        return _records[workflowId][market][keccak256(bytes(updateType))];
    }

    // ============================================================================================
    // Routing
    // ============================================================================================

    /// @inheritdoc AbstractRoutedCreReceiver
    /// @dev Reentrancy defense is two-layered:
    ///      1. `nonReentrant` blocks nested `onReport` (the only entry into `_processReport`).
    ///      2. The route is copied to memory before any external call, so a reentrant path that
    ///         somehow mutated `routes[workflowId]` could not change values used in this frame.
    function _processReport(bytes32 workflowId, bytes calldata report) internal override nonReentrant whenNotPaused {
        Route memory route = routes[workflowId];
        if (route.riskOracle == address(0)) revert RouteNotFound(workflowId);
        if (!route.enabled) revert RouteDisabled(workflowId);

        // Replay guard, expiry half. When the guard is on the workflow wraps the RiskOracle
        // payload in `abi.encode(uint64 signedAt, bytes payload)` where `signedAt` is the
        // consensus timestamp signed into the report. A validly signed report whose first
        // delivery failed stays retryable in the KeystoneForwarder; the age bound caps how
        // long such an artifact stays deliverable even when no newer report has landed.
        uint64 signedAt;
        bytes memory payload;
        if (route.maxReportAgeSeconds != 0) {
            (signedAt, payload) = abi.decode(report, (uint64, bytes));
            if (block.timestamp > uint256(signedAt) + route.maxReportAgeSeconds) {
                revert ReportExpired(workflowId, signedAt, route.maxReportAgeSeconds);
            }
        } else {
            payload = report;
        }

        // Throttle + replay-ordering guard. Skip decode when min-delay is off (0), max-step is
        // off (MAX_STEP_OFF), AND the replay guard is off (signedAt == 0).
        // When max-step is 0 (frozen), we still decode to enforce same-value-only republish.
        // When enabled, decode by selector and apply per-element checks; any trip reverts.
        if (route.minDelaySeconds != 0 || route.maxStepBps != MAX_STEP_OFF || signedAt != 0) {
            if (route.publishSelector == _PUBLISH_SINGLE_SELECTOR) {
                (, bytes memory newValue, string memory updateType, address market,) =
                    abi.decode(payload, (string, bytes, string, address, bytes));
                _checkAndRecord(workflowId, route, market, updateType, newValue, signedAt);
            } else if (route.publishSelector == _PUBLISH_BULK_SELECTOR) {
                (, bytes[] memory newValues, string[] memory updateTypes, address[] memory markets,) =
                    abi.decode(payload, (string[], bytes[], string[], address[], bytes[]));
                for (uint256 i; i < markets.length; i++) {
                    _checkAndRecord(workflowId, route, markets[i], updateTypes[i], newValues[i], signedAt);
                }
            }
            // Unknown selector: fall through. The router cannot decode or enforce max-step or
            // replay ordering on an unknown payload shape (only the expiry check above applies),
            // so operators should use MAX_STEP_OFF to express that the guard is intentionally
            // disabled (or disable the route to freeze all writes).
        }

        // Publish step is load-bearing: revert bubbles up so the workflow can retry.
        (bool ok, bytes memory ret) = route.riskOracle.call(abi.encodePacked(route.publishSelector, payload));
        if (!ok) revert PublishFailed(workflowId, ret);

        emit ReportRouted(workflowId, route.riskOracle, route.publishSelector);

        // Atomic injection. AgentHub is the final guard regardless of caller; we only feed it
        // the agent set and let it decide. Failure must NOT roll back the publish — the oracle
        // record is the source of truth; any later caller can drive check+execute again.
        if (route.agentHub == address(0)) {
            return;
        }

        try IAgentHub(route.agentHub).check(route.agentIds) returns (
            bool shouldExecute, IAgentHub.ActionData[] memory actions
        ) {
            if (!shouldExecute) {
                emit AgentHubKickSkipped(workflowId, "no-actions");
                return;
            }
            try IAgentHub(route.agentHub).execute(actions) {
                emit AgentHubKickResultSuccess(workflowId);
            } catch (bytes memory execErr) {
                emit AgentHubKickResultFailed(workflowId, execErr);
            }
        } catch (bytes memory checkErr) {
            emit AgentHubKickResultFailed(workflowId, checkErr);
        }
    }

    /// @dev Reverts if the throttle check fails; otherwise mutates the record so subsequent
    ///      calls in the same tx see the updated baseline. If the downstream publish reverts,
    ///      EVM rolls back this mutation atomically.
    function _checkAndRecord(
        bytes32 workflowId,
        Route memory route,
        address market,
        string memory updateType,
        bytes memory newValue,
        uint64 signedAt
    )
        internal
    {
        UpdateRecord storage rec = _records[workflowId][market][keccak256(bytes(updateType))];
        uint64 minDelay = route.minDelaySeconds;
        uint64 maxStep = route.maxStepBps;

        // Min-delay: first publish (lastAt == 0) always proceeds.
        uint64 recLastAt = rec.lastAt;
        if (minDelay != 0 && recLastAt != 0 && block.timestamp < uint256(recLastAt) + uint256(minDelay)) {
            revert ThrottleCheckFailed(workflowId, market, updateType);
        }

        // Replay guard, ordering half (signedAt != 0 iff the route's replay guard is on):
        // a report must carry a strictly newer consensus timestamp than the last one
        // published for this key, so a stale signed artifact can never chain onto advanced
        // state. `lastSignedAt` is recorded here, before the publish call: a failed publish
        // reverts the whole tx (`PublishFailed`) and rolls the record back, so it only
        // persists for successful publishes, while AgentHub kick failures are caught after
        // the publish and never skip it.
        if (signedAt != 0) {
            if (signedAt <= rec.lastSignedAt) {
                revert OutOfOrderReport(workflowId, market, updateType, signedAt, rec.lastSignedAt);
            }
            rec.lastSignedAt = signedAt;
        }

        // Max-step: enforced when maxStep is in [0, MAX_BPS] AND payload is 32-byte scalar.
        // MAX_STEP_OFF (type(uint64).max) = guard off, no decode/compare/record.
        // 0 = frozen: any *change* from lastValue rejected; same-value republish passes.
        // 1..MAX_BPS = relative cap with unchanged formula.
        // Tuples / structs / packed bytes bypass the delta check; min-delay still throttles them.
        if (maxStep != MAX_STEP_OFF && newValue.length == 32) {
            uint256 newScalar = abi.decode(newValue, (uint256));
            if (!_withinMaxStep(rec.lastValue, newScalar, maxStep, rec.hasBaseline)) {
                revert ThrottleCheckFailed(workflowId, market, updateType);
            }
            rec.lastValue = newScalar;
            rec.hasBaseline = true;
        }
        rec.lastAt = uint64(block.timestamp);
    }

    /// @dev Returns true iff `|newScalar - last| / last <= maxStepBps / MAX_BPS`.
    ///      Semantics:
    ///      - `!hasBaseline`: warm-up — always pass, caller records baseline
    ///      - `maxStepBps == 0`: frozen — only same-value republish passes (diff must be 0)
    ///      - `maxStepBps in [1, MAX_BPS]`: relative cap, unchanged formula
    ///      (Caller must not pass MAX_STEP_OFF here; that case is filtered upstream.)
    function _withinMaxStep(
        uint256 last,
        uint256 newScalar,
        uint64 maxStepBps,
        bool hasBaseline
    )
        internal
        pure
        returns (bool)
    {
        // Warm-up: no prior baseline to compare — pass and let caller record baseline
        if (!hasBaseline) return true;
        // Frozen (0): only exact same value passes
        if (maxStepBps == 0) return newScalar == last;
        // Relative cap: diff / last <= maxStepBps / MAX_BPS
        uint256 diff = newScalar > last ? newScalar - last : last - newScalar;
        return diff * MAX_BPS <= uint256(maxStepBps) * last;
    }

    function _isContract(address _addr) internal view returns (bool) {
        uint256 size;
        assembly ("memory-safe") { size := extcodesize(_addr) }
        return size > 0;
    }
}
