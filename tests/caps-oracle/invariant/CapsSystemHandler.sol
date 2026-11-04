// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AgentHub } from "chaos-agents/contracts/AgentHub.sol";
import { IAgentHub } from "chaos-agents/interfaces/IAgentHub.sol";
import { IRangeValidationModule } from "chaos-agents/interfaces/IRangeValidationModule.sol";
import { ICapsRangeValidationModule as IRvm } from "../../../src/caps-oracle/interfaces/ICapsRangeValidationModule.sol";
import { ICapsParameterRegistry as IReg } from "../../../src/caps-oracle/interfaces/ICapsParameterRegistry.sol";
import { CapsRangeValidationModuleV3 } from "../../../src/caps-oracle/CapsRangeValidationModuleV3.sol";
import { CapsParameterRegistry } from "../../../src/caps-oracle/CapsParameterRegistry.sol";
import { MockAToken } from "../mocks/MockAToken.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockPoolV3, MockVariableDebtToken } from "../mocks/MockPoolV3.sol";
import { MockRiskOracle } from "../mocks/MockRiskOracle.sol";

/// @title CapsSystemHandler
/// @notice Drives the whole Stage 1 system for the CAP-INV invariants: borrows and repays, interest accrual,
///         supply and withdraw, flash repay-cut-reborrow sequences (CAP-ST-28), raises and cuts through the
///         real AgentHub and the real Aave cap agents, manual cap writes (PoolConfigurator or Risk Steward),
///         hold writes, entry, max cap and bounds writes by each actor (governance executor, Risk Council Safe,
///         and the role-less updater, agent admin, attacker), agent re-registration, frozen and paused toggles,
///         registry writes,
///         and time. Every action picks an asset (WETH 18 decimals, USDC 6 decimals) and a kind (BORROW or
///         SUPPLY), so BORROW and SUPPLY keys mix in every sequence.
/// @dev Ghost flags record a broken property at the moment it happens, for the post-call invariants.
contract CapsSystemHandler is Test {
    uint256 internal constant MAX_CAP = 68_719_476_735;
    uint256 internal constant BPS = 10_000;
    uint256 internal constant NUM_ASSETS = 2;

    struct Deps {
        AgentHub hub;
        CapsRangeValidationModuleV3 rvm;
        MockRiskOracle raiseOracle;
        MockPoolV3 pool;
        CapsParameterRegistry registry;
        address[2] assets;
        MockAToken[2] aTokens;
        uint256[4] ids; // borrow raise, borrow cut, supply raise, supply cut
        address[6] roles; // governance, riskCouncil, updater, agentAdmin, attacker, borrower
    }

    AgentHub public hub;
    CapsRangeValidationModuleV3 public rvm;
    MockRiskOracle public raiseOracle;
    MockPoolV3 public pool;
    CapsParameterRegistry public registry;
    address[2] internal _reserves;
    MockAToken[2] internal _aTokens;
    uint256[4] internal _ids;
    address internal governance;
    address internal riskCouncil;
    address internal updater;
    address internal agentAdmin;
    address internal attacker;
    address internal borrower;

    // ─── Ghosts
    // ───────────────────────────────────────────────────────────────
    bool public ghostAgentWriteAboveMaxCap; // CAP-INV-01
    bool public ghostKindLeak; // CAP-INV-08
    bool public ghostRegistryChangedRvm; // CAP-INV-09
    bool public ghostConfigWroteCap; // CAP-INV-12
    bool public ghostRateLimitConfigOutOfBounds; // CAP-INV-13
    bool public ghostBoundsByNonOwner; // CAP-ACL-01
    bool public ghostRateLimitConfigByNonWriter; // CAP-ACL-04
    bool public ghostHoldByNonWriter; // CAP-ACL-06
    bool public ghostRiskCouncilRaiseRuleBroken; // Risk Council raise limit, cooldown, no listing
    bool public ghostGriefBroke; // CAP-ST-28

    // ─── Call counters (coverage)
    // ─────────────────────────────────────────────
    uint256 public agentRaises;
    uint256 public agentCuts;
    uint256 public griefs;
    uint256 public rateLimitConfigWrites;
    uint256 public holdWrites;
    uint256 public boundsWrites;
    uint256 public registryWrites;

    constructor(Deps memory d) {
        hub = d.hub;
        rvm = d.rvm;
        raiseOracle = d.raiseOracle;
        pool = d.pool;
        registry = d.registry;
        _reserves = d.assets;
        _aTokens = d.aTokens;
        _ids = d.ids;
        governance = d.roles[0];
        riskCouncil = d.roles[1];
        updater = d.roles[2];
        agentAdmin = d.roles[3];
        attacker = d.roles[4];
        borrower = d.roles[5];
        for (uint256 i = 0; i < NUM_ASSETS; i++) {
            vm.prank(borrower);
            IERC20(_reserves[i]).approve(address(pool), type(uint256).max);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // POOL STATE
    // ═══════════════════════════════════════════════════════════════════════════

    function borrow(uint256 assetSeed, uint256 amount) external {
        address a = _asset(assetSeed);
        uint256 capWei = liveCap(a, IRvm.CapKind.BORROW) * _unit(a);
        uint256 debt = _debtToken(a).totalSupply();
        // Half the time inside the free headroom, so debt grows toward the cap and raises follow.
        if (amount % 2 == 0 && capWei > debt + 1) amount = bound(amount, 1, capWei - debt - 1);
        else amount = bound(amount, 1, 300 * _unit(a));
        vm.prank(borrower);
        try pool.borrow(a, amount, 2, 0, borrower) { } catch { }
    }

    function repay(uint256 assetSeed, uint256 amount) external {
        address a = _asset(assetSeed);
        uint256 debt = _debtToken(a).balanceOf(borrower);
        if (debt == 0) return;
        amount = bound(amount, 1, debt);
        _topUp(a, borrower, amount);
        vm.prank(borrower);
        pool.repay(a, amount, 2, borrower);
    }

    /// @dev Interest: the variable borrow index grows by up to 5% per call (no cap, so D can grow past 2^36
    ///      tokens over a long sequence, which exercises CAP-INV-11 on large levels).
    function accrue(uint256 assetSeed, uint256 bps) external {
        address a = _asset(assetSeed);
        uint256 idx = pool.getReserveNormalizedVariableDebt(a);
        uint256 next = idx + (idx * bound(bps, 0, 500)) / BPS;
        if (next > 1e36) return;
        pool.setIndex(a, next);
    }

    function supply(uint256 assetSeed, uint256 amount) external {
        address a = _asset(assetSeed);
        _aTokens[_idx(assetSeed)].mint(address(this), bound(amount, 1, 2000 * _unit(a)));
    }

    function withdraw(uint256 assetSeed, uint256 amount) external {
        MockAToken t = _aTokens[_idx(assetSeed)];
        uint256 bal = t.balanceOf(address(this));
        if (bal == 0) return;
        t.burn(address(this), bound(amount, 1, bal));
    }

    function setFrozen(uint256 assetSeed, bool frozen) external {
        pool.setFrozen(_asset(assetSeed), frozen);
    }

    function setPaused(uint256 assetSeed, bool paused) external {
        pool.setPaused(_asset(assetSeed), paused);
    }

    function warp(uint256 dt) external {
        vm.warp(block.timestamp + bound(dt, 0, 2 days));
        vm.roll(block.number + 1);
    }

    /// @dev A cap write outside the agents: an AIP through PoolConfigurator or a Risk Steward call. Includes 0
    ///      (uncapped) so CAP-INV-07 sees live cap 0.
    function manualCapWrite(uint256 assetSeed, uint256 kindSeed, uint256 cap) external {
        address a = _asset(assetSeed);
        cap = cap % 5 == 0 ? bound(cap, 0, MAX_CAP) : bound(cap, 0, 20_000);
        if (_kind(kindSeed) == IRvm.CapKind.BORROW) pool.setBorrowCap(a, cap);
        else pool.setSupplyCap(a, cap);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // AGENT WRITES THROUGH AGENTHUB
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev The workflow publishes a raise and a keeper runs AgentHub.execute. `mode` picks the preview value,
    ///      a value near the live cap, or any value.
    function raiseViaHub(uint256 assetSeed, uint256 kindSeed, uint256 to, uint256 mode) external {
        address a = _asset(assetSeed);
        IRvm.CapKind k = _kind(kindSeed);
        (uint256 raiseId,) = agentIds(k);
        uint256 cap = liveCap(a, k);
        (bool allowed,, uint256 target) = rvm.previewRaise(a, k);
        uint256 newCap;
        if (mode % 4 < 2 && allowed) newCap = target;
        else if (mode % 4 == 2) newCap = bound(to, cap, cap + 2000);
        else newCap = bound(to, 0, MAX_CAP);
        raiseOracle.publish(updateType(k), a, newCap, cap);
        if (_executeAgent(raiseId, a, k)) ++agentRaises;
    }

    /// @dev A keeper runs AgentHub.execute for the cut agentId; the value comes from CapsReducerOracle.
    function cutViaHub(uint256 assetSeed, uint256 kindSeed) external {
        address a = _asset(assetSeed);
        IRvm.CapKind k = _kind(kindSeed);
        (, uint256 cutId) = agentIds(k);
        if (_executeAgent(cutId, a, k)) ++agentCuts;
    }

    /// @dev CAP-ST-28: the borrower repays x with flash-loaned tokens, runs the cut, borrows x back and repays
    ///      the flash loan, all in one call. Rolled back when the cut or the borrow fails.
    function flashRepayCutReborrow(uint256 assetSeed, uint256 x) external {
        address a = _asset(assetSeed);
        uint256 own = _debtToken(a).balanceOf(borrower);
        if (own == 0) return;
        // Mostly inside (delta L, L], where the grief lands (CAP-ST-28 precondition), sometimes any x.
        x = x % 4 == 0 ? bound(x, 1, own) : bound(x, own / 10 + 1, (own * 9) / 10 + 1);
        uint256 debtBefore = _debtToken(a).totalSupply();
        uint256 capBefore = liveCap(a, IRvm.CapKind.BORROW);
        try this.griefSequence(a, x) {
            ++griefs;
            ++agentCuts;
            uint256 debtAfter = _debtToken(a).totalSupply();
            uint256 capAfter = liveCap(a, IRvm.CapKind.BORROW);
            // Repay floors and borrow ceils the scaled amount, so debt can move by rounding units only.
            uint256 diff = debtAfter > debtBefore ? debtAfter - debtBefore : debtBefore - debtAfter;
            if (diff > 2) ghostGriefBroke = true;
            if (capAfter >= capBefore) ghostGriefBroke = true;
            if (capAfter > effectiveMaxCap(a, IRvm.CapKind.BORROW)) ghostGriefBroke = true;
        } catch { }
    }

    /// @dev Internal step of `flashRepayCutReborrow`. Not a fuzz target (the test lists the selectors).
    function griefSequence(address a, uint256 x) external {
        require(msg.sender == address(this), "self only");
        MockERC20(a).mint(borrower, x); // flash loan
        vm.prank(borrower);
        pool.repay(a, x, 2, borrower);
        (, uint256 cutId) = agentIds(IRvm.CapKind.BORROW);
        if (!_executeAgent(cutId, a, IRvm.CapKind.BORROW)) revert("no cut");
        vm.startPrank(borrower);
        pool.borrow(a, x, 2, 0, borrower);
        IERC20(a).transfer(address(0xdead), x); // flash loan back
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // RVM CONFIGURATION BY EACH ROLE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Around every RVM configuration write: no Pool cap changes (CAP-INV-12) and nothing of the other
    ///      kind changes: entries, holds, bounds, previews and validate results (CAP-INV-08).
    modifier configWrite(IRvm.CapKind k) {
        bytes32 capsBefore = capsDigest();
        IRvm.CapKind other = k == IRvm.CapKind.BORROW ? IRvm.CapKind.SUPPLY : IRvm.CapKind.BORROW;
        bytes32 otherBefore = kindDigest(other);
        _;
        if (capsDigest() != capsBefore) ghostConfigWroteCap = true;
        if (kindDigest(other) != otherBefore) ghostKindLeak = true;
    }

    function setRateLimitConfig(
        uint256 assetSeed,
        uint256 kindSeed,
        uint256 actorSeed,
        uint64 maxCap,
        uint64 maxHeadroom,
        uint16 alphaBps,
        uint16 cutBandBps
    )
        external
        configWrite(_kind(kindSeed))
    {
        IRvm.RateLimitConfig memory e = IRvm.RateLimitConfig({
            maxCap: maxCap % 7 == 0 ? 0 : uint64(bound(maxCap, 1, 6_000_000)),
            maxHeadroom: uint64(bound(maxHeadroom, 20, 2500)),
            alphaBps: uint16(bound(alphaBps, 0, 10_000)),
            cutBandBps: uint16(bound(cutBandBps, 0, 10_000))
        });
        _writeRateLimitConfig(_asset(assetSeed), _kind(kindSeed), _actor(actorSeed), e);
    }

    /// @dev A write of maxCap alone, keeping the stored bps fields. Mostly near the stored maxCap, so Risk Council
    ///      raises inside the relative limit land.
    function setMaxCap(
        uint256 assetSeed,
        uint256 kindSeed,
        uint256 actorSeed,
        uint64 maxCap
    )
        external
        configWrite(_kind(kindSeed))
    {
        address a = _asset(assetSeed);
        IRvm.CapKind k = _kind(kindSeed);
        IRvm.KeyState memory s = rvm.getKeyState(a, k);
        uint256 hi = s.maxCap == 0 ? 6_000_000 : uint256(s.maxCap) * 3 / 2;
        maxCap = uint64(bound(maxCap, 0, hi));
        _writeRateLimitConfig(
            a, k, _actor(actorSeed), IRvm.RateLimitConfig(maxCap, s.maxHeadroom, s.alphaBps, s.cutBandBps)
        );
    }

    function _writeRateLimitConfig(address a, IRvm.CapKind k, address actor, IRvm.RateLimitConfig memory e) internal {
        IRvm.KeyState memory before = rvm.getKeyState(a, k);
        vm.prank(actor);
        try rvm.setRateLimitConfig(a, k, e) {
            ++rateLimitConfigWrites;
            if (actor != governance && actor != riskCouncil) ghostRateLimitConfigByNonWriter = true;
            _checkRateLimitConfigInBounds(a, k);
            if (actor != governance) _checkRiskCouncilRaiseRule(a, k, before);
        } catch { }
    }

    function setBounds(
        uint256 kindSeed,
        uint256 actorSeed,
        uint16 alphaMax,
        uint16 bandMax,
        uint16 increaseBps,
        uint40 cooldown
    )
        external
        configWrite(_kind(kindSeed))
    {
        IRvm.CapKind k = _kind(kindSeed);
        address actor = _actor(actorSeed);
        IRvm.Bounds memory b;
        b.alphaBpsLimit = uint16(bound(alphaMax, 0, 10_000));
        b.cutBandBpsLimit = uint16(bound(bandMax, 0, 10_000));
        b.maxIncreaseBps = uint16(bound(increaseBps, 0, 10_000));
        b.cooldown = uint40(bound(cooldown, 0, 3 days));
        vm.prank(actor);
        try rvm.setBounds(k, b) {
            ++boundsWrites;
            if (actor != governance) ghostBoundsByNonOwner = true;
        } catch { }
    }

    function setHold(
        uint256 assetSeed,
        uint256 kindSeed,
        uint256 actorSeed,
        uint256 dt,
        bool clear
    )
        external
        configWrite(_kind(kindSeed))
    {
        address actor = _actor(actorSeed);
        uint40 until = clear ? 0 : uint40(block.timestamp + bound(dt, 0, 2 days));
        vm.prank(actor);
        try rvm.setHold(_asset(assetSeed), _kind(kindSeed), until) {
            ++holdWrites;
            if (actor != riskCouncil) ghostHoldByNonWriter = true;
        } catch { }
    }

    /// @dev Governance removes and re-adds one agentId with the same direction. The kind is derived again.
    function reRegisterAgent(uint256 idSeed)
        external
        configWrite(idSeed % 4 < 2 ? IRvm.CapKind.BORROW : IRvm.CapKind.SUPPLY)
    {
        uint256 id = _ids[idSeed % 4];
        IRvm.AgentConfig memory c = rvm.getAgent(id);
        vm.startPrank(governance);
        rvm.setAgent(id, IRvm.Direction.NONE);
        rvm.setAgent(id, c.direction);
        vm.stopPrank();
        if (rvm.getAgent(id).kind != c.kind) ghostKindLeak = true;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REGISTRY (CAP-INV-09)
    // ═══════════════════════════════════════════════════════════════════════════

    function registryWrite(uint256 op, uint256 assetSeed, uint256 kindSeed, uint256 v1, uint256 v2) external {
        address a = _asset(assetSeed);
        uint8 k = uint8(_kind(kindSeed));
        bytes32 before = fullDigest();
        vm.startPrank(riskCouncil); // registry updater
        op = op % 4;
        if (op == 0) {
            try registry.setEnabled(address(pool), a, k, IReg.EnabledOverride(v1 % 3)) {
                ++registryWrites;
            } catch { }
        } else if (op == 1) {
            IReg.ReserveOverride memory o = IReg.ReserveOverride({
                enabled: IReg.EnabledOverride(v1 % 3),
                triggerBps: uint16(bound(v2, 0, 10_000)),
                marginBps: uint16(bound(v1 >> 8, 0, 10_000)),
                minMarginTokens: uint64(bound(v2 >> 16, 0, 1000))
            });
            try registry.setReserveOverride(address(pool), a, k, o) {
                ++registryWrites;
            } catch { }
        } else if (op == 2) {
            IReg.MarketParams memory p;
            p.maxBaseFeeGwei = uint64(bound(v2, 0, 1000));
            p.defaultParams = IReg.WorkflowParams({
                enabled: v1 % 2 == 0,
                triggerBps: uint16(bound(v1 >> 8, 0, 10_000)),
                marginBps: uint16(bound(v2 >> 16, 0, 10_000)),
                minMarginTokens: uint64(bound(v1 >> 32, 0, 1000))
            });
            try registry.setMarketParams(address(pool), p) {
                ++registryWrites;
            } catch { }
        } else if (registry.isListed(address(pool), a, k)) {
            try registry.removeReserve(address(pool), a, k) {
                ++registryWrites;
            } catch { }
        } else {
            IReg.ReserveOverride memory none;
            try registry.addReserve(address(pool), a, k, none) {
                ++registryWrites;
            } catch { }
        }
        vm.stopPrank();
        if (fullDigest() != before) ghostRegistryChangedRvm = true;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MODEL HELPERS (also read by the invariant test)
    // ═══════════════════════════════════════════════════════════════════════════

    function assetAt(uint256 i) external view returns (address) {
        return _reserves[i];
    }

    function debtTokenOf(address a) external view returns (address) {
        return address(_debtToken(a));
    }

    function aTokenAt(uint256 i) external view returns (address) {
        return address(_aTokens[i]);
    }

    function agentIds(IRvm.CapKind k) public view returns (uint256 raiseId, uint256 cutId) {
        return k == IRvm.CapKind.BORROW ? (_ids[0], _ids[1]) : (_ids[2], _ids[3]);
    }

    function updateType(IRvm.CapKind k) public pure returns (string memory) {
        return k == IRvm.CapKind.BORROW ? "BorrowCapUpdate_Core" : "SupplyCapUpdate_Core";
    }

    function liveCap(address a, IRvm.CapKind k) public view returns (uint256) {
        (uint256 b, uint256 s) = pool.getReserveCaps(a);
        return k == IRvm.CapKind.BORROW ? b : s;
    }

    /// @dev min(entry.maxCap, 2^36 - 1), the max cap the RVM uses.
    function effectiveMaxCap(address a, IRvm.CapKind k) public view returns (uint256 c) {
        c = rvm.getKeyState(a, k).maxCap;
        if (MAX_CAP < c) c = MAX_CAP;
    }

    /// @dev The stored entry with its bps fields clamped down to the global limits of the kind.
    function clampedRateLimitConfig(address a, IRvm.CapKind k) public view returns (IRvm.RateLimitConfig memory c) {
        IRvm.KeyState memory e = rvm.getKeyState(a, k);
        IRvm.Bounds memory b = rvm.getBounds(k);
        c.maxCap = uint64(effectiveMaxCap(a, k));
        c.maxHeadroom = e.maxHeadroom;
        c.alphaBps = e.alphaBps < b.alphaBpsLimit ? e.alphaBps : b.alphaBpsLimit;
        c.cutBandBps = e.cutBandBps < b.cutBandBpsLimit ? e.cutBandBps : b.cutBandBpsLimit;
    }

    function validateAt(uint256 agentId, address a, uint256 from, uint256 to) public view returns (bool) {
        return rvm.validate(
            address(hub),
            agentId,
            a,
            IRangeValidationModule.RangeValidationInput({ from: from, to: to, updateType: "" })
        );
    }

    /// @dev Every Pool cap of both assets.
    function capsDigest() public view returns (bytes32 h) {
        for (uint256 i = 0; i < NUM_ASSETS; i++) {
            (uint256 b, uint256 s) = pool.getReserveCaps(_reserves[i]);
            h = keccak256(abi.encode(h, b, s));
        }
    }

    /// @dev Everything the RVM stores or returns for one kind: global bounds, and per asset the key slot, both
    ///      previews and two validate results.
    function kindDigest(IRvm.CapKind k) public view returns (bytes32 h) {
        h = keccak256(abi.encode(rvm.getBounds(k)));
        for (uint256 i = 0; i < NUM_ASSETS; i++) {
            h = keccak256(abi.encode(h, _storageDigest(_reserves[i], k), _resultDigest(_reserves[i], k)));
        }
    }

    function fullDigest() public view returns (bytes32) {
        return keccak256(abi.encode(kindDigest(IRvm.CapKind.BORROW), kindDigest(IRvm.CapKind.SUPPLY)));
    }

    function _storageDigest(address a, IRvm.CapKind k) internal view returns (bytes32) {
        return keccak256(abi.encode(rvm.getKeyState(a, k)));
    }

    function _resultDigest(address a, IRvm.CapKind k) internal view returns (bytes32) {
        (uint256 raiseId, uint256 cutId) = agentIds(k);
        (bool r, uint256 c1, uint256 n1) = rvm.previewRaise(a, k);
        (bool d, uint256 c2, uint256 n2) = rvm.previewCut(a, k);
        uint256 cap = liveCap(a, k);
        bool v1 = validateAt(raiseId, a, cap, cap + 1);
        bool v2 = validateAt(cutId, a, cap, cap > 1 ? cap - 1 : 1);
        return keccak256(abi.encode(r, c1, n1, d, c2, n2, v1, v2));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Runs AgentHub.execute for one agentId and asset. On success, every cap the agent changed must be at
    ///      most the effective max cap at that moment (CAP-INV-01).
    function _executeAgent(uint256 agentId, address a, IRvm.CapKind k) internal returns (bool ok) {
        uint256 before = liveCap(a, k);
        IAgentHub.ActionData[] memory ad = new IAgentHub.ActionData[](1);
        ad[0].agentId = agentId;
        ad[0].markets = new address[](1);
        ad[0].markets[0] = a;
        try hub.execute(ad) {
            ok = true;
        } catch { }
        if (!ok) return false;
        uint256 afterCap = liveCap(a, k);
        if (afterCap != before && afterCap > effectiveMaxCap(a, k)) ghostAgentWriteAboveMaxCap = true;
    }

    /// @dev CAP-INV-13: the written bps fields are inside the global limits. A retired entry is always allowed.
    function _checkRateLimitConfigInBounds(address a, IRvm.CapKind k) internal {
        IRvm.KeyState memory e = rvm.getKeyState(a, k);
        if (e.maxCap == 0) return;
        IRvm.Bounds memory b = rvm.getBounds(k);
        if (e.alphaBps > b.alphaBpsLimit || e.cutBandBps > b.cutBandBpsLimit) ghostRateLimitConfigOutOfBounds = true;
    }

    /// @dev After a successful non-owner write: no new key, and a maxCap or maxHeadroom raise within the relative
    ///      limit, after the shared cooldown, with lastIncreaseAt moved to now.
    function _checkRiskCouncilRaiseRule(address a, IRvm.CapKind k, IRvm.KeyState memory before) internal {
        IRvm.KeyState memory s = rvm.getKeyState(a, k);
        if (s.maxCap == 0) return; // retire
        if (before.maxCap == 0) ghostRiskCouncilRaiseRuleBroken = true;
        if (s.maxCap <= before.maxCap && s.maxHeadroom <= before.maxHeadroom) return;
        IRvm.Bounds memory b = rvm.getBounds(k);
        uint256 f = BPS + b.maxIncreaseBps;
        if (
            s.maxCap > uint256(before.maxCap) * f / BPS || s.maxHeadroom > uint256(before.maxHeadroom) * f / BPS
                || block.timestamp < uint256(before.lastIncreaseAt) + b.cooldown || s.lastIncreaseAt != block.timestamp
        ) ghostRiskCouncilRaiseRuleBroken = true;
    }

    function _topUp(address a, address to, uint256 amount) internal {
        uint256 bal = IERC20(a).balanceOf(to);
        if (bal < amount) MockERC20(a).mint(to, amount - bal);
    }

    function _debtToken(address a) internal view returns (MockVariableDebtToken) {
        return MockVariableDebtToken(pool.getReserveVariableDebtToken(a));
    }

    function _idx(uint256 seed) internal pure returns (uint256) {
        return seed % NUM_ASSETS;
    }

    function _asset(uint256 seed) internal view returns (address) {
        return _reserves[seed % NUM_ASSETS];
    }

    function _unit(address a) internal view returns (uint256) {
        return 10 ** MockERC20(a).decimals();
    }

    function _kind(uint256 seed) internal pure returns (IRvm.CapKind) {
        return seed % 2 == 0 ? IRvm.CapKind.BORROW : IRvm.CapKind.SUPPLY;
    }

    /// @dev governance executor, Risk Council Safe, updater, agent admin, attacker.
    function _actor(uint256 seed) internal view returns (address) {
        uint256 i = seed % 5;
        if (i == 0) return governance;
        if (i == 1) return riskCouncil;
        if (i == 2) return updater;
        if (i == 3) return agentAdmin;
        return attacker;
    }
}
