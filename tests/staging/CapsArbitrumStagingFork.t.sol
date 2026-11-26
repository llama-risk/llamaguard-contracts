// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AaveV3Arbitrum, AaveV3ArbitrumAssets } from "aave-address-book/AaveV3Arbitrum.sol";
import { IPool } from "aave-v3-origin/src/contracts/interfaces/IPool.sol";
import { IPoolConfigurator } from "aave-v3-origin/src/contracts/interfaces/IPoolConfigurator.sol";
import { DataTypes } from "aave-v3-origin/src/contracts/protocol/libraries/types/DataTypes.sol";
import {
    ReserveConfiguration
} from "aave-v3-origin/src/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import { IAgentConfigurator } from "chaos-agents/interfaces/IAgentConfigurator.sol";
import { IAgentHub } from "chaos-agents/interfaces/IAgentHub.sol";
import { LlamaguardRiskOracleRouter } from "../../src/LlamaguardRiskOracleRouter.sol";
import { AbstractRoutedCreReceiver } from "../../src/abstracts/AbstractRoutedCreReceiver.sol";
import { ShadowPool } from "../../src/staging/ShadowPool.sol";
import { ICapsParameterRegistry } from "../../src/caps-oracle/interfaces/ICapsParameterRegistry.sol";
import { ICapsRangeValidationModule as IRvm } from "../../src/caps-oracle/interfaces/ICapsRangeValidationModule.sol";
import { CapsConfig } from "../../script/risk-oracles/caps/CapsConfig.sol";
import { CapsDeployment } from "../../script/risk-oracles/caps/CapsDeployment.sol";
import { DeployShadow } from "../../script/risk-oracles/caps/0_DeployShadow.s.sol";
import { DeployCaps } from "../../script/risk-oracles/caps/1_DeployCaps.s.sol";
import { WireCaps } from "../../script/risk-oracles/caps/2_WireCaps.s.sol";
import { ConfigureAssets } from "../../script/risk-oracles/caps/3_ConfigureAssets.s.sol";
import { AddRoute } from "../../script/risk-oracles/caps/4_AddRoute.s.sol";

/// @title CapsArbitrumStagingFork
/// @notice Steps 0 to 4 on the staging config against the live Aave V3 Arbitrum Pool, then the raise and cut loop
///         on the ShadowPool: the real Pool and its caps never change.
/// @dev Skips unless `ARBITRUM_RPC_URL` is set and the profile is `fork`:
///        ARBITRUM_RPC_URL=... FOUNDRY_PROFILE=fork forge test --match-path 'tests/staging/*Fork*'
///      The roles and the route come from this test, the market and asset values from the committed files.
contract CapsArbitrumStagingForkTest is Test {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    string internal constant LABEL = "arbitrum-core-staging";
    bytes32 internal constant WORKFLOW_ID = keccak256("caps-arbitrum-staging-fork");
    bytes10 internal constant WORKFLOW_NAME = bytes10("capsarbstg");

    IPool internal constant REAL_POOL = AaveV3Arbitrum.POOL;
    address internal constant WETH = AaveV3ArbitrumAssets.WETH_UNDERLYING;
    address internal constant GHO = AaveV3ArbitrumAssets.GHO_UNDERLYING;

    address internal eoa = makeAddr("stagingEoa");
    address internal forwarder = makeAddr("keystoneForwarder");
    address internal workflowOwner = makeAddr("workflowOwner");
    address internal keeper = makeAddr("keeper");
    address internal borrower = makeAddr("borrower");

    bool internal forked;
    CapsDeployment.Deployment internal d;
    ShadowPool internal shadow;
    IRvm internal rvm;
    IAgentConfigurator internal hub;
    LlamaguardRiskOracleRouter internal router;
    string internal updateType;

    function setUp() public {
        string memory rpc = vm.envOr("ARBITRUM_RPC_URL", string(""));
        if (bytes(rpc).length == 0 || keccak256(bytes(vm.envOr("FOUNDRY_PROFILE", string("")))) != keccak256("fork")) {
            return;
        }
        vm.createSelectFork(rpc);
        forked = true;

        CapsConfig.Config memory config = _config();
        updateType = CapsConfig.borrowUpdateType(config.market);
        d = new DeployShadow().deployShadow(config, d, eoa);
        d = new DeployCaps().deploy(config, d, eoa);
        d = new WireCaps().wire(config, d, eoa);
        new ConfigureAssets().configureAssets(config, d, eoa);
        new AddRoute().addRoute(config.market, _route(), d, WORKFLOW_ID, WORKFLOW_NAME, eoa);

        shadow = ShadowPool(d.shadowPool);
        rvm = IRvm(d.rvm);
        hub = IAgentConfigurator(d.agentHub);
        router = LlamaguardRiskOracleRouter(d.router);
    }

    modifier onlyForked() {
        if (!forked) vm.skip(true);
        _;
    }

    // ─── what the steps leave behind
    // ────────────────────────────────────────

    /// @dev Every check of the workflow's wiring gate (domain/gates.ts), read from chain.
    function test_wiring_passesTheWorkflowGate() public onlyForked {
        (
            address riskOracle,
            bytes4 selector,
            address agentHub,
            bool enabled,
            uint64 minDelay,
            uint64 maxStep,
            uint64 age
        ) = router.routes(WORKFLOW_ID);
        assertEq(riskOracle, d.riskOracle, "route RiskOracle");
        assertEq(
            selector, bytes4(keccak256("publishBulkRiskParameterUpdates(string[],bytes[],string[],address[],bytes[])"))
        );
        assertEq(agentHub, d.agentHub, "route AgentHub");
        assertTrue(enabled, "route enabled");
        assertEq(minDelay, 0, "route min delay off");
        assertEq(maxStep, router.MAX_STEP_OFF(), "route step guard off");
        assertGe(age, 360, "report age");
        assertEq(router.getAgentIds(WORKFLOW_ID)[0], d.raiseAgentId, "route kicks the raise agent");

        assertEq(hub.getRiskOracle(d.raiseAgentId), d.riskOracle, "raise agent oracle");
        assertEq(hub.getRiskOracle(d.cutAgentId), d.reducer, "cut agent oracle");
        assertTrue(hub.isPermissionedSender(d.raiseAgentId, d.router), "only the Router kicks the raise agent");
        assertTrue(hub.isPermissionedSender(d.cutAgentId, d.router), "only the Router kicks the cut agent");
        assertTrue(hub.isMarketsFromAgentEnabled(d.raiseAgentId), "markets from the Pool");
        assertLe(hub.getExpirationPeriod(d.raiseAgentId), 600, "expiry within the workflow's limit");
        assertEq(hub.getMinimumDelay(d.raiseAgentId), 1800, "tau");
        assertEq(
            abi.decode(hub.getAgentContext(d.raiseAgentId), (address)), d.shadowPool, "agents write the ShadowPool"
        );
        assertEq(hub.getUpdateType(d.raiseAgentId), updateType, "update type");

        IRvm.AgentConfig memory raise = rvm.getAgent(d.raiseAgentId);
        assertEq(uint8(raise.direction), uint8(IRvm.Direction.RAISE), "RVM raise agent");
        assertEq(uint8(raise.kind), uint8(IRvm.CapKind.BORROW), "RVM borrow kind");
        assertEq(ICapsParameterRegistry(d.registry).getMarketParams(d.shadowPool).rvm, d.rvm, "registry market");
    }

    function test_beforeAnyWrite_theShadowPoolReadsAavesCaps() public onlyForked {
        CapsConfig.Reserve[] memory reserves = _config().assets.reserves;
        for (uint256 i; i < reserves.length; ++i) {
            address asset = reserves[i].asset;
            assertEq(shadow.getConfiguration(asset).data, REAL_POOL.getConfiguration(asset).data, reserves[i].symbol);
            assertFalse(shadow.hasShadowCap(asset), reserves[i].symbol);
        }
    }

    function test_rvmEntries_capAtTodaysCap() public onlyForked {
        CapsConfig.Reserve[] memory reserves = _config().assets.reserves;
        for (uint256 i; i < reserves.length; ++i) {
            IRvm.ReserveState memory s = rvm.getReserveState(reserves[i].asset, IRvm.CapKind.BORROW);
            assertEq(s.maxCap, _realCap(reserves[i].asset), reserves[i].symbol);
        }
    }

    // ─── the loop on live debt
    // ──────────────────────────────────────────────

    function test_cut_landsOnTheShadowCapOnly() public onlyForked {
        uint256 realCap = _realCap(WETH);
        (bool due,, uint256 newCap) = rvm.previewCut(WETH, IRvm.CapKind.BORROW);
        assertTrue(due, "WETH has more room than (1 + delta) * L today");

        _cut(WETH);

        assertEq(shadow.borrowCap(WETH), newCap, "cut to debt + L");
        assertEq(_realCap(WETH), realCap, "Aave's cap unchanged");
        assertEq(hub.getLastInjectedUpdate(d.cutAgentId, WETH).timestamp, block.timestamp, "hub recorded the cut");
    }

    function test_raise_throughTheRouter_landsOnTheShadowCapOnly() public onlyForked {
        _cut(WETH);
        _borrowUntilRaiseIsDue(WETH);
        (bool allowed, uint256 currentCap, uint256 newCap) = rvm.previewRaise(WETH, IRvm.CapKind.BORROW);
        assertTrue(allowed && newCap > currentCap, "raise accepted");
        uint256 realCap = _realCap(WETH);

        _publish(WETH, newCap);

        assertEq(shadow.borrowCap(WETH), newCap, "raise landed");
        assertEq(_realCap(WETH), realCap, "Aave's cap unchanged");
        assertEq(hub.getLastInjectedUpdate(d.raiseAgentId, WETH).timestamp, block.timestamp, "hub recorded the raise");
    }

    /// @dev AgentHub's minimumDelay is the only pacing of raises: a second report inside tau publishes to the
    ///      RiskOracle, but the agent skips it and the cap stays.
    function test_raise_withinTau_isSkippedByTheHub() public onlyForked {
        _cut(WETH);
        _borrowUntilRaiseIsDue(WETH);
        (,, uint256 first) = rvm.previewRaise(WETH, IRvm.CapKind.BORROW);
        _publish(WETH, first);

        vm.warp(block.timestamp + 10 minutes);
        _borrowUntilRaiseIsDue(WETH);
        (bool allowed,, uint256 second) = rvm.previewRaise(WETH, IRvm.CapKind.BORROW);
        assertTrue(allowed && second > first, "the RVM would take a second raise");
        _publish(WETH, second);
        assertEq(shadow.borrowCap(WETH), first, "held until tau");

        vm.warp(block.timestamp + 30 minutes);
        (,, second) = rvm.previewRaise(WETH, IRvm.CapKind.BORROW);
        _publish(WETH, second);
        assertEq(shadow.borrowCap(WETH), second, "lands after tau");
    }

    /// @dev Real borrowers only meet Aave's cap, so live debt can pass the shadow cap: the borrows production would
    ///      have stopped. The RVM then raises from the debt.
    function test_debtAboveTheShadowCap_isVisibleAndRaisable() public onlyForked {
        _cut(WETH);
        uint256 shadowCap = shadow.borrowCap(WETH);
        _borrowTokens(WETH, shadowCap - _debt(WETH) + 50);

        IRvm.ReserveState memory s = rvm.getReserveState(WETH, IRvm.CapKind.BORROW);
        assertGt(s.usage, s.cap, "debt above the shadow cap");
        (bool allowed,, uint256 newCap) = rvm.previewRaise(WETH, IRvm.CapKind.BORROW);
        assertTrue(allowed && newCap > s.usage, "raise above the debt");
        _publish(WETH, newCap);
        assertEq(shadow.borrowCap(WETH), newCap, "raise landed");
    }

    // ─── Aave's own cap
    // ─────────────────────────────────────────────────────

    function test_aaveCapChange_isFollowedOnlyBeforeOurFirstWrite() public onlyForked {
        uint256 realCap = _realCap(GHO);
        _setRealCap(GHO, realCap + 1000);
        assertEq(shadow.borrowCap(GHO), realCap + 1000, "followed before our first write");

        _cut(WETH); // a write on another asset changes nothing for GHO
        _setRealCap(GHO, realCap + 2000);
        assertEq(shadow.borrowCap(GHO), realCap + 2000, "still followed");

        vm.prank(d.cutAgent);
        shadow.setBorrowCap(GHO, realCap);
        _setRealCap(GHO, realCap + 3000);
        assertEq(shadow.borrowCap(GHO), realCap, "ours after the first write");
    }

    // ─── failure modes
    // ──────────────────────────────────────────────────────

    function test_agentNotAWriter_theCutReverts() public onlyForked {
        vm.prank(eoa);
        shadow.setWriter(d.cutAgent, false);
        vm.prank(d.router);
        vm.expectRevert(abi.encodeWithSelector(ShadowPool.NotWriter.selector, d.cutAgent));
        IAgentHub(d.agentHub).execute(_actions(d.cutAgentId, WETH));
    }

    function test_reportFromAnotherSender_isRejected() public onlyForked {
        vm.expectRevert(
            abi.encodeWithSelector(AbstractRoutedCreReceiver.InvalidForwarder.selector, address(this), forwarder)
        );
        router.onReport(_metadata(), abi.encode(uint64(block.timestamp), _payload(WETH, 1)));
    }

    /// @dev Drops the last configured reserve, as if a listing had been missed.
    function test_coverage_revertsOnAMissingBorrowableReserve() public onlyForked {
        CapsConfig.Assets memory assets = _config().assets;
        CapsConfig.Reserve[] memory reserves = assets.reserves;
        address dropped = reserves[reserves.length - 1].asset;
        assembly ("memory-safe") {
            mstore(reserves, sub(mload(reserves), 1))
        }
        ConfigureAssets step = new ConfigureAssets();
        vm.expectRevert(
            bytes(
                string.concat(
                    "ConfigureAssets: borrowable reserve not in the asset values file: ", vm.toString(dropped)
                )
            )
        );
        step.checkCoverage(IPool(d.shadowPool), assets);
    }

    /// @dev Every real reserve stays covered; one extra entry names an address that is not a reserve.
    function test_coverage_revertsOnAnAssetThatIsNotAReserve() public onlyForked {
        CapsConfig.Assets memory assets = _config().assets;
        CapsConfig.Reserve[] memory reserves = new CapsConfig.Reserve[](assets.reserves.length + 1);
        for (uint256 i; i < assets.reserves.length; ++i) {
            reserves[i] = assets.reserves[i];
        }
        reserves[assets.reserves.length].symbol = "NOTAR";
        reserves[assets.reserves.length].asset = makeAddr("notAReserve");
        assets.reserves = reserves;
        ConfigureAssets step = new ConfigureAssets();
        vm.expectRevert(bytes("ConfigureAssets: not a reserve of the Pool: NOTAR"));
        step.checkCoverage(IPool(d.shadowPool), assets);
    }

    /// @dev Production path: a sender that holds no role sends nothing, so the Safes get every call as a batch.
    function test_configureAssets_sendsNothingTheSenderCannotSign() public onlyForked {
        ConfigureAssets step = new ConfigureAssets();
        vm.expectCall(d.rvm, abi.encodeWithSelector(IRvm.setRateLimitConfig.selector), 0);
        vm.expectCall(d.registry, abi.encodeWithSelector(ICapsParameterRegistry.addReserve.selector), 0);
        step.configureAssets(_config(), d, makeAddr("holdsNoRole"));
    }

    // ─── helpers
    // ────────────────────────────────────────────────────────────

    function _config() internal view returns (CapsConfig.Config memory config) {
        config.market = CapsConfig.loadMarket(LABEL);
        config.assets = CapsConfig.loadAssets(config.market.assets);
        config.roles = CapsConfig.Roles({
            deployer: eoa,
            agentHubOwner: eoa,
            agentAdmin: eoa,
            shadowPoolOwner: eoa,
            riskOracleOwner: eoa,
            routerOwner: eoa,
            routerUpdater: eoa,
            routerGuardian: eoa,
            registryOwner: eoa,
            registryUpdater: eoa,
            rvmOwner: eoa,
            riskCouncil: eoa
        });
    }

    function _route() internal view returns (CapsConfig.Route memory) {
        return CapsConfig.Route({ forwarder: forwarder, workflowOwner: workflowOwner, maxReportAgeSeconds: 360 });
    }

    function _realCap(address asset) internal view returns (uint256) {
        return REAL_POOL.getConfiguration(asset).getBorrowCap();
    }

    function _debt(address asset) internal view returns (uint256) {
        return rvm.getReserveState(asset, IRvm.CapKind.BORROW).usage;
    }

    function _setRealCap(address asset, uint256 cap) internal {
        vm.prank(AaveV3Arbitrum.ACL_ADMIN);
        IPoolConfigurator(address(AaveV3Arbitrum.POOL_CONFIGURATOR)).setBorrowCap(asset, cap);
    }

    function test_cutFromAnotherSender_isSkippedByTheHub() public onlyForked {
        vm.prank(keeper);
        vm.expectRevert(IAgentHub.NoActionCanBePerformed.selector);
        IAgentHub(d.agentHub).execute(_actions(d.cutAgentId, WETH));
    }

    function _cut(address asset) internal {
        vm.prank(d.router);
        IAgentHub(d.agentHub).execute(_actions(d.cutAgentId, asset));
    }

    /// @dev A real borrow on the real Pool, against the borrower's own supply.
    function _borrowTokens(address asset, uint256 tokens) internal {
        uint256 amount = tokens * 1e18;
        deal(asset, borrower, amount * 2);
        vm.startPrank(borrower);
        IERC20(asset).approve(address(REAL_POOL), amount * 2);
        REAL_POOL.supply(asset, amount * 2, borrower, 0);
        REAL_POOL.borrow(asset, amount, 2, 0, borrower);
        vm.stopPrank();
    }

    /// @dev Borrows until the room under the shadow cap is at most theta * L, so a raise is due.
    function _borrowUntilRaiseIsDue(address asset) internal {
        IRvm.ReserveState memory s = rvm.getReserveState(asset, IRvm.CapKind.BORROW);
        uint256 room = s.cap > s.usage ? s.cap - s.usage : 0;
        uint256 dueAt = s.headroomTarget * 2000 / 10_000;
        if (room > dueAt) _borrowTokens(asset, room - dueAt + 1);
    }

    /// @dev What the KeystoneForwarder delivers: route metadata and the enveloped bulk report.
    function _publish(address asset, uint256 cap) internal {
        vm.prank(forwarder);
        router.onReport(_metadata(), abi.encode(uint64(block.timestamp), _payload(asset, cap)));
    }

    function _payload(address asset, uint256 cap) internal view returns (bytes memory) {
        string[] memory refs = new string[](1);
        refs[0] = string.concat("fork-", vm.toString(block.timestamp));
        bytes[] memory values = new bytes[](1);
        values[0] = abi.encode(cap);
        string[] memory types = new string[](1);
        types[0] = updateType;
        address[] memory markets = new address[](1);
        markets[0] = asset;
        return abi.encode(refs, values, types, markets, new bytes[](1));
    }

    /// @dev The forwarder metadata layout: workflowId, bytes10 name, author.
    function _metadata() internal view returns (bytes memory) {
        return abi.encodePacked(WORKFLOW_ID, WORKFLOW_NAME, workflowOwner);
    }

    function _actions(uint256 agentId, address asset) internal pure returns (IAgentHub.ActionData[] memory a) {
        a = new IAgentHub.ActionData[](1);
        a[0].agentId = agentId;
        a[0].markets = new address[](1);
        a[0].markets[0] = asset;
    }
}
