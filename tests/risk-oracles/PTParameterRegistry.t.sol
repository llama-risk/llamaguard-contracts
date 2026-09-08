// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";
import { PTParameterRegistry } from "../../src/PTParameterRegistry.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract PTParameterRegistryTest is Test {
    event DeviationThresholdBpsSet(address indexed market, uint64 thresholdBps);
    event KReferenceEndpointSet(address indexed market, uint64 kReferenceEndpoint);

    PTParameterRegistry internal registry;

    address internal owner = makeAddr("owner");
    address internal updater = makeAddr("updater");
    address internal rando = makeAddr("rando");
    address internal market = makeAddr("market");
    address internal market2 = makeAddr("market2");

    function setUp() public {
        registry = new PTParameterRegistry(owner, updater);
    }

    function _baselineParams() internal pure returns (PTParameterRegistry.PtMarketParams memory p) {
        uint16[] memory ids = new uint16[](2);
        ids[0] = 1;
        ids[1] = 7;
        p = PTParameterRegistry.PtMarketParams({
            enabled: true,
            modelVersion: 1,
            emaSpan: 100,
            emaFreshnessSeconds: 7200,
            thresholdBps: 30,
            kReferenceEndpoint: 25_000,
            emodeCategoryIds: ids
        });
    }

    // ============================================================================================
    // Constructor
    // ============================================================================================

    function test_constructor_setsOwnerAndUpdater() public view {
        assertEq(registry.owner(), owner);
        assertEq(registry.updater(), updater);
        assertEq(registry.MAX_BPS(), 10_000);
        assertEq(registry.K_FACTOR_SCALE(), 10_000);
    }

    function test_constructor_revertsOnZeroUpdater() public {
        vm.expectRevert(PTParameterRegistry.ZeroAddress.selector);
        new PTParameterRegistry(owner, address(0));
    }

    // ============================================================================================
    // setUpdater
    // ============================================================================================

    function test_setUpdater_onlyOwner() public {
        address newUpdater = makeAddr("newUpdater");
        vm.prank(owner);
        registry.setUpdater(newUpdater);
        assertEq(registry.updater(), newUpdater);
    }

    function test_setUpdater_revertsForNonOwner() public {
        vm.prank(rando);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, rando));
        registry.setUpdater(rando);
    }

    function test_setUpdater_revertsOnZero() public {
        vm.prank(owner);
        vm.expectRevert(PTParameterRegistry.ZeroAddress.selector);
        registry.setUpdater(address(0));
    }

    // ============================================================================================
    // setPtMarketParams
    // ============================================================================================

    function test_setPtMarketParams_storesAndEmits() public {
        PTParameterRegistry.PtMarketParams memory p = _baselineParams();
        vm.prank(updater);
        registry.setPtMarketParams(market, p);

        assertTrue(registry.marketExists(market));
        PTParameterRegistry.PtMarketParams memory got = registry.getPtMarketParams(market);
        assertEq(got.thresholdBps, 30);
        assertEq(got.emodeCategoryIds.length, 2);
        assertEq(got.emodeCategoryIds[1], 7);
    }

    function test_setPtMarketParams_revertsForNonUpdater() public {
        PTParameterRegistry.PtMarketParams memory p = _baselineParams();
        vm.prank(owner);
        vm.expectRevert(PTParameterRegistry.OnlyUpdater.selector);
        registry.setPtMarketParams(market, p);
    }

    function test_setPtMarketParams_revertsOnZeroMarket() public {
        PTParameterRegistry.PtMarketParams memory p = _baselineParams();
        vm.prank(updater);
        vm.expectRevert(PTParameterRegistry.ZeroAddress.selector);
        registry.setPtMarketParams(address(0), p);
    }

    function test_setPtMarketParams_revertsOnInvalidEmaSpan() public {
        PTParameterRegistry.PtMarketParams memory p = _baselineParams();
        p.emaSpan = 0;
        vm.prank(updater);
        vm.expectRevert(PTParameterRegistry.InvalidEmaSpan.selector);
        registry.setPtMarketParams(market, p);
    }

    function test_setPtMarketParams_revertsOnEmptyEmodeIds() public {
        PTParameterRegistry.PtMarketParams memory p = _baselineParams();
        p.emodeCategoryIds = new uint16[](0);
        vm.prank(updater);
        vm.expectRevert(PTParameterRegistry.EmptyEmodeCategoryIds.selector);
        registry.setPtMarketParams(market, p);
    }

    function test_setPtMarketParams_revertsOnZeroKReferenceEndpoint() public {
        PTParameterRegistry.PtMarketParams memory p = _baselineParams();
        p.kReferenceEndpoint = 0;
        vm.prank(updater);
        vm.expectRevert(PTParameterRegistry.InvalidKReferenceEndpoint.selector);
        registry.setPtMarketParams(market, p);
    }

    function testFuzz_setPtMarketParams_rejectsBpsAboveCap(uint64 bps) public {
        bps = uint64(bound(bps, uint256(registry.MAX_BPS()) + 1, type(uint64).max));
        PTParameterRegistry.PtMarketParams memory p = _baselineParams();
        p.thresholdBps = bps;
        vm.prank(updater);
        vm.expectRevert(abi.encodeWithSelector(PTParameterRegistry.BpsTooHigh.selector, bps));
        registry.setPtMarketParams(market, p);
    }

    // ============================================================================================
    // Per-field setters
    // ============================================================================================

    function _seedMarket() internal {
        vm.prank(updater);
        registry.setPtMarketParams(market, _baselineParams());
    }

    function test_setEnabled_flipsAndRequiresExists() public {
        _seedMarket();
        vm.prank(updater);
        registry.setEnabled(market, false);
        assertEq(registry.getPtMarketParams(market).enabled, false);

        vm.prank(updater);
        vm.expectRevert(PTParameterRegistry.MarketNotFound.selector);
        registry.setEnabled(market2, true);
    }

    function test_setModelVersion_storesAndEmits() public {
        _seedMarket();
        vm.prank(updater);
        registry.setModelVersion(market, 42);
        assertEq(registry.getPtMarketParams(market).modelVersion, 42);
    }

    function test_setEmaSpan_validatesNonZero() public {
        _seedMarket();
        vm.prank(updater);
        vm.expectRevert(PTParameterRegistry.InvalidEmaSpan.selector);
        registry.setEmaSpan(market, 0);

        vm.prank(updater);
        registry.setEmaSpan(market, 200);
        assertEq(registry.getPtMarketParams(market).emaSpan, 200);
    }

    function test_setEmaFreshnessSeconds_validatesNonZero() public {
        _seedMarket();
        vm.prank(updater);
        vm.expectRevert(PTParameterRegistry.InvalidEmaFreshness.selector);
        registry.setEmaFreshnessSeconds(market, 0);
    }

    function test_setDeviationThresholdBps_storesAndEmits() public {
        _seedMarket();
        vm.expectEmit(true, false, false, true, address(registry));
        emit DeviationThresholdBpsSet(market, 50);
        vm.prank(updater);
        registry.setDeviationThresholdBps(market, 50);
        assertEq(registry.getPtMarketParams(market).thresholdBps, 50);
    }

    function test_setDeviationThresholdBps_revertsOnBpsTooHigh() public {
        _seedMarket();
        uint64 bps = registry.MAX_BPS() + 1;
        vm.prank(updater);
        vm.expectRevert(abi.encodeWithSelector(PTParameterRegistry.BpsTooHigh.selector, bps));
        registry.setDeviationThresholdBps(market, bps);
    }

    function test_setDeviationThresholdBps_revertsOnMarketNotFound() public {
        vm.prank(updater);
        vm.expectRevert(PTParameterRegistry.MarketNotFound.selector);
        registry.setDeviationThresholdBps(market, 50);
    }

    function test_setKReferenceEndpoint_storesAndEmits() public {
        _seedMarket();
        vm.expectEmit(true, false, false, true, address(registry));
        emit KReferenceEndpointSet(market, 30_000);
        vm.prank(updater);
        registry.setKReferenceEndpoint(market, 30_000);
        assertEq(registry.getPtMarketParams(market).kReferenceEndpoint, 30_000);
    }

    function test_setKReferenceEndpoint_revertsOnZero() public {
        _seedMarket();
        vm.prank(updater);
        vm.expectRevert(PTParameterRegistry.InvalidKReferenceEndpoint.selector);
        registry.setKReferenceEndpoint(market, 0);
    }

    function test_setKReferenceEndpoint_revertsOnMarketNotFound() public {
        vm.prank(updater);
        vm.expectRevert(PTParameterRegistry.MarketNotFound.selector);
        registry.setKReferenceEndpoint(market, 30_000);
    }

    function test_setEmodeCategoryIds_replacesArray() public {
        _seedMarket();
        uint16[] memory ids = new uint16[](3);
        ids[0] = 9;
        ids[1] = 10;
        ids[2] = 11;
        vm.prank(updater);
        registry.setEmodeCategoryIds(market, ids);
        uint16[] memory got = registry.getEmodeCategoryIds(market);
        assertEq(got.length, 3);
        assertEq(got[2], 11);
    }

    function test_setEmodeCategoryIds_revertsOnEmpty() public {
        _seedMarket();
        uint16[] memory empty = new uint16[](0);
        vm.prank(updater);
        vm.expectRevert(PTParameterRegistry.EmptyEmodeCategoryIds.selector);
        registry.setEmodeCategoryIds(market, empty);
    }

    function test_deleteMarket_clearsState() public {
        _seedMarket();
        vm.prank(updater);
        registry.deleteMarket(market);
        assertFalse(registry.marketExists(market));
        vm.expectRevert(PTParameterRegistry.MarketNotFound.selector);
        registry.getPtMarketParams(market);
    }

    function test_deleteMarket_revertsIfMissing() public {
        vm.prank(updater);
        vm.expectRevert(PTParameterRegistry.MarketNotFound.selector);
        registry.deleteMarket(market);
    }

    // ============================================================================================
    // Two-step ownership
    // ============================================================================================

    function test_twoStepOwnership_pendingOwnerCannotActAsOwner() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        registry.transferOwnership(newOwner);
        assertEq(registry.pendingOwner(), newOwner);
        assertEq(registry.owner(), owner);

        // pendingOwner cannot setUpdater yet
        vm.prank(newOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, newOwner));
        registry.setUpdater(makeAddr("anotherUpdater"));

        // accept transfer
        vm.prank(newOwner);
        registry.acceptOwnership();
        assertEq(registry.owner(), newOwner);

        // now the new owner can set updater
        vm.prank(newOwner);
        registry.setUpdater(makeAddr("anotherUpdater"));
    }

    // ============================================================================================
    // Fuzz — full PtMarketParams round-trip
    // ============================================================================================

    /// @dev Asserts that any valid PtMarketParams configuration survives a store → read
    ///      round-trip with byte-for-byte fidelity. Fuzzes the dynamic `emodeCategoryIds[]`
    ///      and a representative subset of scalars (one per slice + the boolean) on top of
    ///      `_baselineParams()`. The remaining scalars are exercised by the dedicated unit
    ///      tests above.
    function testFuzz_setPtMarketParams_roundTrip(
        uint16[] memory rawIds,
        uint64 thresholdBps_,
        uint64 emaFreshnessSeconds_,
        uint64 kReferenceEndpoint_,
        bool enabled_
    )
        public
    {
        // Bound the fuzzed scalars to the validator's accepted ranges.
        emaFreshnessSeconds_ = uint64(bound(emaFreshnessSeconds_, 1, type(uint64).max));
        thresholdBps_ = uint64(bound(thresholdBps_, 0, registry.MAX_BPS()));
        kReferenceEndpoint_ = uint64(bound(kReferenceEndpoint_, 1, type(uint64).max));

        // Non-empty emodeCategoryIds; cap length so the fuzz runs in reasonable time.
        uint256 len = bound(rawIds.length, 1, 16);
        uint16[] memory ids = new uint16[](len);
        for (uint256 i; i < len; i++) {
            ids[i] = i < rawIds.length ? rawIds[i] : uint16(i + 1);
        }

        PTParameterRegistry.PtMarketParams memory p = _baselineParams();
        p.enabled = enabled_;
        p.thresholdBps = thresholdBps_;
        p.emaFreshnessSeconds = emaFreshnessSeconds_;
        p.kReferenceEndpoint = kReferenceEndpoint_;
        p.emodeCategoryIds = ids;

        vm.prank(updater);
        registry.setPtMarketParams(market, p);

        PTParameterRegistry.PtMarketParams memory got = registry.getPtMarketParams(market);
        assertEq(got.enabled, p.enabled);
        assertEq(got.modelVersion, p.modelVersion);
        assertEq(got.emaSpan, p.emaSpan);
        assertEq(got.emaFreshnessSeconds, p.emaFreshnessSeconds);
        assertEq(got.thresholdBps, p.thresholdBps);
        assertEq(got.kReferenceEndpoint, p.kReferenceEndpoint);
        assertEq(got.emodeCategoryIds.length, p.emodeCategoryIds.length);
        for (uint256 i; i < ids.length; i++) {
            assertEq(got.emodeCategoryIds[i], ids[i]);
        }
    }
}
