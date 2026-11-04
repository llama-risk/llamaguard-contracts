// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IRiskOracle } from "chaos-agents/contracts/dependencies/IRiskOracle.sol";
import { CapsTestBase } from "./CapsTestBase.sol";
import { MockCapsRvm } from "./mocks/MockCapsRvm.sol";
import { CapsParameterRegistry } from "../../src/caps-oracle/CapsParameterRegistry.sol";
import { CapsReducerOracle } from "../../src/caps-oracle/CapsReducerOracle.sol";
import { ICapsParameterRegistry as IReg } from "../../src/caps-oracle/interfaces/ICapsParameterRegistry.sol";
import { ICapsRangeValidationModule as IRvm } from "../../src/caps-oracle/interfaces/ICapsRangeValidationModule.sol";

/// @notice Shared registry setup: owner LlamaRisk Safe, updater Risk Council Safe, one market
///         (the mock Core Pool) with the default parameters.
abstract contract RegistryTestBase is CapsTestBase {
    uint8 internal constant BORROW = 0;
    uint8 internal constant SUPPLY = 1;

    CapsParameterRegistry internal registry;
    address internal market; // Ethereum Core stand-in

    function setUp() public virtual override {
        super.setUp();
        market = address(pool);
        registry = new CapsParameterRegistry(llamaRiskSafe, riskCouncil);
        vm.prank(riskCouncil);
        registry.addMarket(market, _marketParams());
    }

    /// TODO(params): theta, margin, margin floor and max base fee are placeholders
    /// (CapsTestBase constants).
    function _marketParams() internal pure returns (IReg.MarketParams memory p) {
        p.maxBaseFeeGwei = MAX_BASE_FEE_GWEI;
        p.defaultParams = IReg.WorkflowParams({
            enabled: true, triggerBps: THETA_BPS, marginBps: MARGIN_BPS, minMarginTokens: MIN_MARGIN_TOKENS
        });
    }

    function _noOverride() internal pure returns (IReg.ReserveOverride memory o) { }

    function _override(uint16 triggerBps) internal pure returns (IReg.ReserveOverride memory o) {
        o.triggerBps = triggerBps;
    }

    function _add(address asset, uint8 kind, IReg.ReserveOverride memory o) internal {
        vm.prank(riskCouncil);
        registry.addReserve(market, asset, kind, o);
    }
}

contract CapsParameterRegistryTest is RegistryTestBase {
    // ═══════════════════════════════════════════════════════════════════════════
    // CAP-ST-32 registry key overrides the market default
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CAP_ST_32_getEffectiveParams_overrideThenDefault() public {
        // Example: market default triggerBps 2000. (Core, WETH, BORROW) override 1500 returns 1500.
        // (Core, USDC, BORROW) with no override returns 2000.
        _add(address(weth), BORROW, _override(1500));
        _add(address(usdc), BORROW, _noOverride());

        assertEq(registry.getEffectiveParams(market, address(weth), BORROW).triggerBps, 1500);
        assertEq(registry.getEffectiveParams(market, address(usdc), BORROW).triggerBps, THETA_BPS);
    }

    function test_CAP_ST_32_getEffectiveParams_eachFieldFallsBackAlone() public {
        IReg.ReserveOverride memory o;
        o.marginBps = 300;
        _add(address(weth), BORROW, o);

        IReg.WorkflowParams memory p = registry.getEffectiveParams(market, address(weth), BORROW);
        assertTrue(p.enabled, "enabled INHERIT -> market default (true)");
        assertEq(p.triggerBps, THETA_BPS, "trigger 0 -> default");
        assertEq(p.marginBps, 300, "margin override");
        assertEq(p.minMarginTokens, MIN_MARGIN_TOKENS, "floor 0 -> default");

        o.minMarginTokens = 5;
        o.marginBps = 0;
        vm.prank(riskCouncil);
        registry.setReserveOverride(market, address(weth), BORROW, o);
        p = registry.getEffectiveParams(market, address(weth), BORROW);
        assertEq(p.marginBps, MARGIN_BPS, "margin back to default");
        assertEq(p.minMarginTokens, 5, "floor override");
    }

    function test_CAP_ST_32_enabledOverride_onOffDefault() public {
        _add(address(weth), BORROW, _noOverride());

        vm.startPrank(riskCouncil);
        registry.setEnabled(market, address(weth), BORROW, IReg.EnabledOverride.OFF);
        assertFalse(registry.getEffectiveParams(market, address(weth), BORROW).enabled, "OFF");

        // Market default off: ON on the key still enables it, INHERIT follows the market.
        IReg.MarketParams memory mp = _marketParams();
        mp.defaultParams.enabled = false;
        registry.setMarketParams(market, mp);
        registry.setEnabled(market, address(weth), BORROW, IReg.EnabledOverride.ON);
        assertTrue(registry.getEffectiveParams(market, address(weth), BORROW).enabled, "ON over default off");
        registry.setEnabled(market, address(weth), BORROW, IReg.EnabledOverride.INHERIT);
        assertFalse(registry.getEffectiveParams(market, address(weth), BORROW).enabled, "INHERIT -> off");
        vm.stopPrank();
    }

    function test_CAP_ST_32_marketDefaultChange_reachesKeysWithoutOverride() public {
        _add(address(weth), BORROW, _override(1500));
        _add(address(usdc), BORROW, _noOverride());

        IReg.MarketParams memory mp = _marketParams();
        mp.defaultParams.triggerBps = 2500;
        vm.prank(riskCouncil);
        registry.setMarketParams(market, mp);

        assertEq(registry.getEffectiveParams(market, address(weth), BORROW).triggerBps, 1500, "override kept");
        assertEq(registry.getEffectiveParams(market, address(usdc), BORROW).triggerBps, 2500, "default moved");
    }

    function test_CAP_ST_32_getEffectiveParams_unlisted_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(IReg.ReserveNotFound.selector, market, address(weth), BORROW));
        registry.getEffectiveParams(market, address(weth), BORROW);
    }

    function test_CAP_ST_32_fuzz_overrideOrDefault(uint16 trigger, uint16 margin, uint64 floor, uint8 sw) public {
        trigger = uint16(bound(trigger, 0, 10_000));
        margin = uint16(bound(margin, 0, 10_000));
        IReg.ReserveOverride memory o = IReg.ReserveOverride({
            enabled: IReg.EnabledOverride(sw % 3), triggerBps: trigger, marginBps: margin, minMarginTokens: floor
        });
        _add(address(weth), BORROW, o);
        IReg.WorkflowParams memory p = registry.getEffectiveParams(market, address(weth), BORROW);
        IReg.WorkflowParams memory d = _marketParams().defaultParams;

        assertEq(p.triggerBps, trigger != 0 ? trigger : d.triggerBps);
        assertEq(p.marginBps, margin != 0 ? margin : d.marginBps);
        assertEq(p.minMarginTokens, floor != 0 ? floor : d.minMarginTokens);
        assertEq(
            p.enabled, o.enabled == IReg.EnabledOverride.INHERIT ? d.enabled : o.enabled == IReg.EnabledOverride.ON
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CAP-ST-33 registry kind isolation
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CAP_ST_33_setReserveOverride_leavesOtherKindAtDefault() public {
        // Example: setReserveOverride(Core, WETH, BORROW, 1500) leaves (Core, WETH, SUPPLY) at 2000.
        _add(address(weth), BORROW, _noOverride());
        _add(address(weth), SUPPLY, _noOverride());

        vm.prank(riskCouncil);
        registry.setReserveOverride(market, address(weth), BORROW, _override(1500));

        assertEq(registry.getEffectiveParams(market, address(weth), BORROW).triggerBps, 1500);
        assertEq(registry.getEffectiveParams(market, address(weth), SUPPLY).triggerBps, THETA_BPS);
    }

    function test_CAP_ST_33_setEnabledAndRemove_touchOneKeyOnly() public {
        _add(address(weth), BORROW, _override(1500));
        _add(address(weth), SUPPLY, _override(1200));
        _add(address(usdc), BORROW, _override(1100));

        vm.startPrank(riskCouncil);
        registry.setEnabled(market, address(weth), SUPPLY, IReg.EnabledOverride.OFF);
        registry.removeReserve(market, address(weth), BORROW);
        vm.stopPrank();

        assertFalse(registry.isListed(market, address(weth), BORROW));
        IReg.WorkflowParams memory s = registry.getEffectiveParams(market, address(weth), SUPPLY);
        assertFalse(s.enabled);
        assertEq(s.triggerBps, 1200);
        IReg.WorkflowParams memory u = registry.getEffectiveParams(market, address(usdc), BORROW);
        assertTrue(u.enabled);
        assertEq(u.triggerBps, 1100);
    }

    function test_CAP_ST_33_sameAssetTwoMarkets_isolated() public {
        address prime = makeAddr("primePool");
        vm.startPrank(riskCouncil);
        registry.addMarket(prime, _marketParams());
        registry.addReserve(market, address(weth), BORROW, _noOverride());
        registry.addReserve(prime, address(weth), BORROW, _noOverride());
        registry.setReserveOverride(prime, address(weth), BORROW, _override(900));
        vm.stopPrank();

        assertEq(registry.getEffectiveParams(market, address(weth), BORROW).triggerBps, THETA_BPS);
        assertEq(registry.getEffectiveParams(prime, address(weth), BORROW).triggerBps, 900);
    }

    function test_CAP_ST_33_removeThenReAdd_startsClean() public {
        _add(address(weth), BORROW, _override(1500));
        vm.startPrank(riskCouncil);
        registry.setEnabled(market, address(weth), BORROW, IReg.EnabledOverride.OFF);
        registry.removeReserve(market, address(weth), BORROW);
        registry.addReserve(market, address(weth), BORROW, _noOverride());
        vm.stopPrank();

        IReg.WorkflowParams memory p = registry.getEffectiveParams(market, address(weth), BORROW);
        assertTrue(p.enabled, "old OFF switch gone");
        assertEq(p.triggerBps, THETA_BPS, "old override gone");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CAP-ACL-14 registry access
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CAP_ACL_14_registry_unauthorised_reverts() public {
        _add(address(weth), BORROW, _noOverride());
        address[2] memory callers = [attacker, llamaRiskSafe]; // the owner is not the updater either
        for (uint256 i = 0; i < callers.length; i++) {
            vm.startPrank(callers[i]);
            vm.expectRevert(IReg.OnlyUpdater.selector);
            registry.addMarket(makeAddr("m"), _marketParams());
            vm.expectRevert(IReg.OnlyUpdater.selector);
            registry.setMarketParams(market, _marketParams());
            vm.expectRevert(IReg.OnlyUpdater.selector);
            registry.removeMarket(market);
            vm.expectRevert(IReg.OnlyUpdater.selector);
            registry.addReserve(market, address(usdc), BORROW, _noOverride());
            vm.expectRevert(IReg.OnlyUpdater.selector);
            registry.setReserveOverride(market, address(weth), BORROW, _override(1));
            vm.expectRevert(IReg.OnlyUpdater.selector);
            registry.setEnabled(market, address(weth), BORROW, IReg.EnabledOverride.OFF);
            vm.expectRevert(IReg.OnlyUpdater.selector);
            registry.removeReserve(market, address(weth), BORROW);
            vm.stopPrank();
        }

        // Only the owner appoints the updater; the updater itself cannot.
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        registry.setUpdater(attacker);
        vm.prank(riskCouncil);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, riskCouncil));
        registry.setUpdater(riskCouncil);
    }

    function test_CAP_ACL_14_ownerSetsUpdater_succeeds() public {
        vm.expectEmit(address(registry));
        emit IReg.UpdaterChanged(riskCouncil, updater);
        vm.prank(llamaRiskSafe);
        registry.setUpdater(updater);
        assertEq(registry.updater(), updater);

        // The old updater lost the role, the new one has it.
        vm.prank(riskCouncil);
        vm.expectRevert(IReg.OnlyUpdater.selector);
        registry.setEnabled(market, address(weth), BORROW, IReg.EnabledOverride.OFF);
        vm.prank(updater);
        registry.addReserve(market, address(weth), BORROW, _noOverride());
        assertTrue(registry.isListed(market, address(weth), BORROW));
    }

    function test_CAP_ACL_14_setUpdater_zero_reverts() public {
        vm.prank(llamaRiskSafe);
        vm.expectRevert(IReg.ZeroAddress.selector);
        registry.setUpdater(address(0));
    }

    function test_CAP_ACL_14_constructor_rolesSet() public {
        assertEq(registry.owner(), llamaRiskSafe);
        assertEq(registry.updater(), riskCouncil, "updater = Risk Council Safe at deploy");
        vm.expectRevert(IReg.ZeroAddress.selector);
        new CapsParameterRegistry(llamaRiskSafe, address(0));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new CapsParameterRegistry(address(0), riskCouncil);
    }

    function test_CAP_ACL_14_ownership_twoStep() public {
        vm.prank(llamaRiskSafe);
        registry.transferOwnership(governance);
        assertEq(registry.owner(), llamaRiskSafe, "pending only");

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        registry.acceptOwnership();

        vm.prank(governance);
        registry.acceptOwnership();
        assertEq(registry.owner(), governance);
        vm.prank(governance);
        registry.setUpdater(updater);
        assertEq(registry.updater(), updater);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARKETS: bounds and lifecycle
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Registry_addMarket_storesAndLists() public {
        address prime = makeAddr("primePool");
        IReg.MarketParams memory mp = _marketParams();
        mp.maxBaseFeeGwei = 0; // 0 = no gas gate
        mp.rvm = makeAddr("primeRvm");
        vm.expectEmit(address(registry));
        emit IReg.MarketAdded(prime, mp);
        vm.prank(riskCouncil);
        registry.addMarket(prime, mp);

        address[] memory markets = registry.getMarkets();
        assertEq(markets.length, 2);
        assertEq(markets[1], prime);
        IReg.MarketParams memory got = registry.getMarketParams(prime);
        assertEq(got.maxBaseFeeGwei, 0);
        assertEq(got.defaultParams.triggerBps, THETA_BPS);
        assertEq(got.rvm, makeAddr("primeRvm"), "RVM per market");
        assertEq(registry.getMarketParams(market).rvm, address(0), "the other market keeps its own (unset) RVM");
        assertEq(registry.getReservesList(prime).length, 0);
    }

    function test_Registry_addMarket_invalid_reverts() public {
        IReg.MarketParams memory mp = _marketParams();
        vm.startPrank(riskCouncil);

        vm.expectRevert(IReg.ZeroAddress.selector);
        registry.addMarket(address(0), mp);

        vm.expectRevert(abi.encodeWithSelector(IReg.MarketAlreadyExists.selector, market));
        registry.addMarket(market, mp);

        address prime = makeAddr("primePool");
        mp.defaultParams.triggerBps = 0; // a default theta of 0 never triggers
        vm.expectRevert(abi.encodeWithSelector(IReg.InvalidBps.selector, uint16(0)));
        registry.addMarket(prime, mp);

        mp.defaultParams.triggerBps = 10_001;
        vm.expectRevert(abi.encodeWithSelector(IReg.InvalidBps.selector, uint16(10_001)));
        registry.addMarket(prime, mp);

        mp.defaultParams.triggerBps = 10_000;
        mp.defaultParams.marginBps = 10_001;
        vm.expectRevert(abi.encodeWithSelector(IReg.InvalidBps.selector, uint16(10_001)));
        registry.addMarket(prime, mp);

        // Edges accepted: trigger 10_000, margin 0 (a market default margin can be 0).
        mp.defaultParams.marginBps = 0;
        registry.addMarket(prime, mp);
        vm.stopPrank();
    }

    function test_Registry_setMarketParams_unknownOrInvalid_reverts() public {
        address prime = makeAddr("primePool");
        vm.startPrank(riskCouncil);
        vm.expectRevert(abi.encodeWithSelector(IReg.MarketNotFound.selector, prime));
        registry.setMarketParams(prime, _marketParams());

        IReg.MarketParams memory mp = _marketParams();
        mp.defaultParams.triggerBps = 0;
        vm.expectRevert(abi.encodeWithSelector(IReg.InvalidBps.selector, uint16(0)));
        registry.setMarketParams(market, mp);

        mp.defaultParams.triggerBps = 3000;
        mp.maxBaseFeeGwei = 80;
        mp.rvm = makeAddr("newRvm");
        vm.expectEmit(address(registry));
        emit IReg.MarketParamsSet(market, mp);
        registry.setMarketParams(market, mp);
        assertEq(registry.getMarketParams(market).maxBaseFeeGwei, 80);
        assertEq(registry.getMarketParams(market).rvm, makeAddr("newRvm"));

        // address(0) is accepted and means "not set".
        mp.rvm = address(0);
        registry.setMarketParams(market, mp);
        vm.stopPrank();
        assertEq(registry.getMarketParams(market).rvm, address(0));
    }

    function test_Registry_removeMarket_needsEmptyWorkList() public {
        _add(address(weth), BORROW, _noOverride());
        vm.startPrank(riskCouncil);
        vm.expectRevert(abi.encodeWithSelector(IReg.MarketNotEmpty.selector, market));
        registry.removeMarket(market);

        registry.removeReserve(market, address(weth), BORROW);
        vm.expectEmit(address(registry));
        emit IReg.MarketRemoved(market);
        registry.removeMarket(market);

        vm.expectRevert(abi.encodeWithSelector(IReg.MarketNotFound.selector, market));
        registry.removeMarket(market);
        vm.stopPrank();

        assertEq(registry.getMarkets().length, 0);
        vm.expectRevert(abi.encodeWithSelector(IReg.MarketNotFound.selector, market));
        registry.getMarketParams(market);
        vm.expectRevert(abi.encodeWithSelector(IReg.MarketNotFound.selector, market));
        registry.getReservesList(market);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // WORK LIST: bounds and lifecycle
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Registry_addReserve_listsAndEmits() public {
        IReg.ReserveOverride memory o = _override(1500);
        vm.expectEmit(address(registry));
        emit IReg.ReserveAdded(market, address(weth), BORROW, o);
        _add(address(weth), BORROW, o);
        _add(address(weth), SUPPLY, _noOverride());
        _add(address(wbtc), BORROW, _noOverride());

        IReg.ReserveKey[] memory keys = registry.getReservesList(market);
        assertEq(keys.length, 3);
        assertEq(keys[0].asset, address(weth));
        assertEq(keys[0].kind, BORROW);
        assertEq(keys[1].asset, address(weth));
        assertEq(keys[1].kind, SUPPLY);
        assertEq(keys[2].asset, address(wbtc));
        assertTrue(registry.isListed(market, address(weth), SUPPLY));
        assertFalse(registry.isListed(market, address(usdc), BORROW));
        assertEq(registry.getReserveOverride(market, address(weth), BORROW).triggerBps, 1500);
    }

    function test_Registry_addReserve_invalid_reverts() public {
        address prime = makeAddr("primePool");
        vm.startPrank(riskCouncil);
        vm.expectRevert(abi.encodeWithSelector(IReg.MarketNotFound.selector, prime));
        registry.addReserve(prime, address(weth), BORROW, _noOverride());

        vm.expectRevert(abi.encodeWithSelector(IReg.InvalidKind.selector, uint8(2)));
        registry.addReserve(market, address(weth), 2, _noOverride());

        vm.expectRevert(IReg.ZeroAddress.selector);
        registry.addReserve(market, address(0), BORROW, _noOverride());

        vm.expectRevert(abi.encodeWithSelector(IReg.InvalidBps.selector, uint16(10_001)));
        registry.addReserve(market, address(weth), BORROW, _override(10_001));

        IReg.ReserveOverride memory o;
        o.marginBps = 10_001;
        vm.expectRevert(abi.encodeWithSelector(IReg.InvalidBps.selector, uint16(10_001)));
        registry.addReserve(market, address(weth), BORROW, o);

        registry.addReserve(market, address(weth), BORROW, _override(10_000));
        vm.expectRevert(abi.encodeWithSelector(IReg.ReserveAlreadyListed.selector, market, address(weth), BORROW));
        registry.addReserve(market, address(weth), BORROW, _noOverride());
        vm.stopPrank();
    }

    function test_Registry_keyWrites_unlistedOrBadKind_revert() public {
        vm.startPrank(riskCouncil);
        vm.expectRevert(abi.encodeWithSelector(IReg.ReserveNotFound.selector, market, address(weth), BORROW));
        registry.setReserveOverride(market, address(weth), BORROW, _override(1500));
        vm.expectRevert(abi.encodeWithSelector(IReg.ReserveNotFound.selector, market, address(weth), BORROW));
        registry.setEnabled(market, address(weth), BORROW, IReg.EnabledOverride.OFF);
        vm.expectRevert(abi.encodeWithSelector(IReg.ReserveNotFound.selector, market, address(weth), BORROW));
        registry.removeReserve(market, address(weth), BORROW);
        vm.expectRevert(abi.encodeWithSelector(IReg.InvalidKind.selector, uint8(3)));
        registry.setReserveOverride(market, address(weth), 3, _override(1500));

        registry.addReserve(market, address(weth), BORROW, _noOverride());
        vm.expectRevert(abi.encodeWithSelector(IReg.InvalidBps.selector, uint16(20_000)));
        registry.setReserveOverride(market, address(weth), BORROW, _override(20_000));
        vm.stopPrank();
    }

    function test_Registry_keyWrites_emit() public {
        _add(address(weth), BORROW, _noOverride());
        vm.startPrank(riskCouncil);
        vm.expectEmit(address(registry));
        emit IReg.ReserveOverrideSet(market, address(weth), BORROW, _override(1500));
        registry.setReserveOverride(market, address(weth), BORROW, _override(1500));
        vm.expectEmit(address(registry));
        emit IReg.EnabledSet(market, address(weth), BORROW, IReg.EnabledOverride.OFF);
        registry.setEnabled(market, address(weth), BORROW, IReg.EnabledOverride.OFF);
        vm.expectEmit(address(registry));
        emit IReg.ReserveRemoved(market, address(weth), BORROW);
        registry.removeReserve(market, address(weth), BORROW);
        vm.stopPrank();
        assertEq(registry.getReserveOverride(market, address(weth), BORROW).triggerBps, 0, "override cleared");
    }

    function test_Registry_anyAsset_noTokenFilter(address asset) public {
        // Decision 0014: any address can be listed, with no token filter.
        vm.assume(asset != address(0));
        _add(asset, BORROW, _noOverride());
        assertTrue(registry.isListed(market, asset, BORROW));
        IReg.ReserveKey[] memory keys = registry.getReservesList(market);
        assertEq(keys[0].asset, asset);
        assertEq(keys[0].kind, BORROW);
    }
}

/// @notice Handler for the registry invariants. It acts as the updater on a small key universe and keeps a
///         ghost copy of every stored value, so the invariant can check that each write touched only its key.
contract RegistryHandler is Test {
    CapsParameterRegistry internal registry;
    address internal updaterAddr;
    address internal market;
    address[] internal assets;

    // Ghost state per key index (asset index * 2 + kind).
    mapping(uint256 => bool) public ghostListed;
    mapping(uint256 => IReg.ReserveOverride) internal _ghostOverride;
    IReg.WorkflowParams internal _ghostDefaultParams;

    constructor(
        CapsParameterRegistry registry_,
        address updater_,
        address market_,
        address[] memory assets_,
        IReg.WorkflowParams memory defaultParams
    ) {
        registry = registry_;
        updaterAddr = updater_;
        market = market_;
        assets = assets_;
        _ghostDefaultParams = defaultParams;
    }

    function keyCount() external view returns (uint256) {
        return assets.length * 2;
    }

    function keyAt(uint256 k) public view returns (address asset, uint8 kind) {
        asset = assets[k / 2];
        kind = uint8(k % 2);
    }

    function ghostOverride(uint256 k) external view returns (IReg.ReserveOverride memory) {
        return _ghostOverride[k];
    }

    function ghostDefaultParams() external view returns (IReg.WorkflowParams memory) {
        return _ghostDefaultParams;
    }

    function addReserve(uint256 seed, uint16 trigger, uint16 margin, uint64 floor, uint8 sw) external {
        uint256 k = seed % (assets.length * 2);
        if (ghostListed[k]) return;
        (address asset, uint8 kind) = keyAt(k);
        IReg.ReserveOverride memory o = _mkOverride(trigger, margin, floor, sw);
        vm.prank(updaterAddr);
        registry.addReserve(market, asset, kind, o);
        ghostListed[k] = true;
        _ghostOverride[k] = o;
    }

    function setReserveOverride(uint256 seed, uint16 trigger, uint16 margin, uint64 floor, uint8 sw) external {
        uint256 k = seed % (assets.length * 2);
        if (!ghostListed[k]) return;
        (address asset, uint8 kind) = keyAt(k);
        IReg.ReserveOverride memory o = _mkOverride(trigger, margin, floor, sw);
        vm.prank(updaterAddr);
        registry.setReserveOverride(market, asset, kind, o);
        _ghostOverride[k] = o;
    }

    function setEnabled(uint256 seed, uint8 sw) external {
        uint256 k = seed % (assets.length * 2);
        if (!ghostListed[k]) return;
        (address asset, uint8 kind) = keyAt(k);
        IReg.EnabledOverride s = IReg.EnabledOverride(sw % 3);
        vm.prank(updaterAddr);
        registry.setEnabled(market, asset, kind, s);
        _ghostOverride[k].enabled = s;
    }

    function removeReserve(uint256 seed) external {
        uint256 k = seed % (assets.length * 2);
        if (!ghostListed[k]) return;
        (address asset, uint8 kind) = keyAt(k);
        vm.prank(updaterAddr);
        registry.removeReserve(market, asset, kind);
        ghostListed[k] = false;
        delete _ghostOverride[k];
    }

    function setMarketDefaultParams(bool enabled, uint16 trigger, uint16 margin, uint64 floor, uint64 gas) external {
        IReg.MarketParams memory mp;
        mp.maxBaseFeeGwei = gas;
        mp.defaultParams = IReg.WorkflowParams({
            enabled: enabled,
            triggerBps: uint16(bound(trigger, 1, 10_000)),
            marginBps: uint16(bound(margin, 0, 10_000)),
            minMarginTokens: floor
        });
        vm.prank(updaterAddr);
        registry.setMarketParams(market, mp);
        _ghostDefaultParams = mp.defaultParams;
    }

    function _mkOverride(
        uint16 trigger,
        uint16 margin,
        uint64 floor,
        uint8 sw
    )
        internal
        pure
        returns (IReg.ReserveOverride memory o)
    {
        o.enabled = IReg.EnabledOverride(sw % 3);
        o.triggerBps = uint16(bound(trigger, 0, 10_000));
        o.marginBps = uint16(bound(margin, 0, 10_000));
        o.minMarginTokens = floor;
    }
}

/// @notice Invariants CAP-ST-33 (registry key isolation) and CAP-INV-09 (registry independence).
/// @dev CAP-INV-09 here runs against the mock RVM and CapsReducerOracle: no registry write changes what the RVM
///      or the oracle return, and no registry write touches RVM storage. The full version, with
///      CapsRangeValidationModuleV3 `previewRaise` under F1, belongs with the RVM tests.
contract CapsParameterRegistryInvariantTest is RegistryTestBase {
    RegistryHandler internal handler;
    MockCapsRvm internal rvm;
    CapsReducerOracle internal oracle;

    function setUp() public virtual override {
        super.setUp();
        address[] memory assets = new address[](3);
        assets[0] = address(weth);
        assets[1] = address(usdc);
        assets[2] = address(wbtc);
        handler = new RegistryHandler(registry, riskCouncil, market, assets, _marketParams().defaultParams);

        rvm = new MockCapsRvm();
        rvm.setCut(address(weth), IRvm.CapKind.BORROW, true, 1200, F1_CUT_FLOOR);
        rvm.setRateLimitConfig(address(weth), IRvm.CapKind.BORROW, _rateLimitConfigOf(_f1()));
        oracle = new CapsReducerOracle(IRvm(address(rvm)), IRvm.CapKind.BORROW);

        targetContract(address(handler));
    }

    function invariant_CAP_ST_33_registryKeyIsolation() public view {
        IReg.WorkflowParams memory d = handler.ghostDefaultParams();
        uint256 listed;
        for (uint256 k = 0; k < handler.keyCount(); k++) {
            (address asset, uint8 kind) = handler.keyAt(k);
            bool isListed = handler.ghostListed(k);
            assertEq(registry.isListed(market, asset, kind), isListed, "listed flag");
            if (!isListed) continue;
            listed++;

            IReg.ReserveOverride memory o = handler.ghostOverride(k);
            IReg.ReserveOverride memory stored = registry.getReserveOverride(market, asset, kind);
            assertEq(uint8(stored.enabled), uint8(o.enabled), "stored switch");
            assertEq(stored.triggerBps, o.triggerBps, "stored trigger");
            assertEq(stored.marginBps, o.marginBps, "stored margin");
            assertEq(stored.minMarginTokens, o.minMarginTokens, "stored floor");

            IReg.WorkflowParams memory p = registry.getEffectiveParams(market, asset, kind);
            assertEq(
                p.enabled, o.enabled == IReg.EnabledOverride.INHERIT ? d.enabled : o.enabled == IReg.EnabledOverride.ON
            );
            assertEq(p.triggerBps, o.triggerBps != 0 ? o.triggerBps : d.triggerBps);
            assertEq(p.marginBps, o.marginBps != 0 ? o.marginBps : d.marginBps);
            assertEq(p.minMarginTokens, o.minMarginTokens != 0 ? o.minMarginTokens : d.minMarginTokens);
        }
        assertEq(registry.getReservesList(market).length, listed, "work list length");
    }

    function invariant_CAP_INV_09_registryIndependence() public view {
        (bool due, uint256 cur, uint256 newCap) = rvm.previewCut(address(weth), IRvm.CapKind.BORROW);
        assertTrue(due);
        assertEq(cur, 1200);
        assertEq(newCap, F1_CUT_FLOOR);
        IRiskOracle.RiskParameterUpdate memory u =
            IRiskOracle(address(oracle)).getLatestUpdateByParameterAndMarket(BORROW_UPDATE_TYPE, address(weth));
        assertEq(abi.decode(u.newValue, (uint256)), F1_CUT_FLOOR);
        assertEq(rvm.getRateLimitConfig(address(weth), IRvm.CapKind.BORROW).maxCap, F1_MAX_CAP);
    }
}

/// @notice CAP-INV-09 unit form: registry writes reach no other contract.
contract CapsParameterRegistryIndependenceTest is RegistryTestBase {
    function test_CAP_INV_09_registryWrites_touchNoOtherContract() public {
        MockCapsRvm rvm = new MockCapsRvm();
        rvm.setRateLimitConfig(address(weth), IRvm.CapKind.BORROW, _rateLimitConfigOf(_f1()));

        vm.record();
        vm.startPrank(riskCouncil);
        registry.addReserve(market, address(weth), BORROW, _noOverride());
        registry.setEnabled(market, address(weth), BORROW, IReg.EnabledOverride.OFF); // enabled false
        IReg.MarketParams memory mp = _marketParams();
        mp.defaultParams.triggerBps = 1; // lowest allowed default theta
        registry.setMarketParams(market, mp);
        registry.setReserveOverride(market, address(weth), BORROW, _override(10_000));
        registry.removeReserve(market, address(weth), BORROW);
        vm.stopPrank();

        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(rvm));
        assertEq(reads.length, 0, "registry reads no RVM storage on writes");
        assertEq(writes.length, 0, "registry writes no RVM storage");
        (, writes) = vm.accesses(address(pool));
        assertEq(writes.length, 0, "registry writes no Pool storage");
        assertEq(rvm.getRateLimitConfig(address(weth), IRvm.CapKind.BORROW).maxCap, F1_MAX_CAP);
    }
}
