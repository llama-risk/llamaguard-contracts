// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { ICapsRangeValidationModule as IRvm } from "../../src/caps-oracle/interfaces/ICapsRangeValidationModule.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockPoolV3, MockVariableDebtToken } from "./mocks/MockPoolV3.sol";
import { MockRiskSteward } from "./mocks/MockRiskSteward.sol";
import { MockSafe } from "./mocks/MockSafe.sol";

/// @title CapsTestBase
/// @notice Shared fixtures for the Caps Oracle Stage 1 tests: role addresses, a mock Aave V3 Pool with three
///         reserves (18, 6 and 8 decimals), the worked-example fixtures F1 and F2, and the placeholder parameters.
/// @dev The base deploys no Stage 1 contract, so each test file deploys the contract under test in its own
///      `setUp` after `super.setUp()`. All amounts of a fixture are whole tokens; `_wei` converts to the
///      smallest unit of an asset.
abstract contract CapsTestBase is Test {
    // ═══════════════════════════════════════════════════════════════════════════
    // ROLES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev RVM owner and AgentHub owner on Ethereum (the Aave Executor).
    address internal governance = makeAddr("governanceExecutor");
    /// @dev Risk Council Safe: RVM `riskCouncil`, Steward `RISK_COUNCIL`, forwarder `RISK_COUNCIL`.
    ///      Tests that need it to act as a Safe call `_etchSafeAtRiskCouncil()`.
    address internal riskCouncil = makeAddr("riskCouncilSafe");
    /// @dev Has no RVM role. Kept as a distinct caller for the access tests.
    address internal updater = makeAddr("updater");
    /// @dev Agent admin (Protocol Guardian). Has no RVM role (CAP-ACL-08).
    address internal agentAdmin = makeAddr("agentAdmin");
    /// @dev Has no role anywhere.
    address internal attacker = makeAddr("attacker");
    /// @dev Large borrower for the forwarder tests.
    address internal borrower = makeAddr("borrower");
    /// @dev LlamaRisk Safe: owner of CapsParameterRegistry .
    address internal llamaRiskSafe = makeAddr("llamaRiskSafe");
    /// @dev AgentHub address. A plain address; tests that need AgentHub behaviour use the real contract.
    address internal agentHub = makeAddr("agentHub");

    // ═══════════════════════════════════════════════════════════════════════════
    // AGENT IDS AND UPDATE TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    uint256 internal constant RAISE_AGENT_ID = 1;
    uint256 internal constant CUT_AGENT_ID = 2;
    string internal constant BORROW_UPDATE_TYPE = "BorrowCapUpdate_Core";
    string internal constant SUPPLY_UPDATE_TYPE = "SupplyCapUpdate_Core";

    // ═══════════════════════════════════════════════════════════════════════════
    // PLACEHOLDER PARAMETERS. All are TODO(params): they live only in tests.
    // ═══════════════════════════════════════════════════════════════════════════

    /// TODO(params): alpha, buffer as a share of debt. Placeholder: 10%.
    uint16 internal constant ALPHA_BPS = 1000;
    /// TODO(params): delta, band. Placeholder: 10% of L.
    uint16 internal constant CUT_CUT_BAND_BPS = 1000;
    /// TODO(params): theta, trigger. Placeholder: 20% of L. Registry only, the RVM never reads it.
    uint16 internal constant THETA_BPS = 2000;
    /// TODO(params): raise margin as a share of L. Placeholder: max(1% of L, 1 token).
    uint16 internal constant MARGIN_BPS = 100;
    /// TODO(params): raise margin floor, whole tokens. Placeholder: 1 token.
    uint64 internal constant MIN_MARGIN_TOKENS = 1;
    /// TODO(params): max base fee in gwei. Placeholder: 50 gwei.
    uint64 internal constant MAX_BASE_FEE_GWEI = 50;
    /// TODO(params): tau, raise agentId `minimumDelay`, seconds. Placeholder: 1800.
    uint256 internal constant TAU = 1800;
    /// TODO(params): `expirationPeriod` of the raise agentId, seconds. Placeholder: 86400.
    uint256 internal constant EXPIRATION_PERIOD = 86_400;
    /// Longest hold, equals the RVM `MAX_HOLD_DURATION` (24 h). Fixed by the interface, not a placeholder.
    uint256 internal constant MAX_HOLD_DURATION = 86_400;
    /// Largest cap value Aave stores (36 bits). CAP-UNIT-03.
    uint256 internal constant MAX_AAVE_CAP = 68_719_476_735;

    /// Risk Council maxCap and maxHeadroom raise limit per cooldown: +100%, as the Aave Risk Steward cap rule.
    uint16 internal constant MAX_INCREASE_BPS = 10_000;
    /// TODO(params): cooldown between two Risk Council raises, seconds. Placeholder: 1 day.
    uint40 internal constant COOLDOWN = 1 days;

    /// TODO(params): global BORROW bounds. Chosen so
    /// that F1 and F2 sit inside them.
    function _globalBorrowBounds() internal pure returns (IRvm.Bounds memory b) {
        b = IRvm.Bounds({
            alphaBpsLimit: 5000, cutBandBpsLimit: 5000, maxIncreaseBps: MAX_INCREASE_BPS, cooldown: COOLDOWN
        });
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FIXTURES F1 AND F2
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice One worked-example fixture. All amounts are whole tokens of an 18-decimal asset unless the
    ///         test says otherwise. `supply` is S as a Pool supply cap.
    struct Fixture {
        uint256 debt; // D
        uint64 maxCap; // C-bar
        uint64 maxHeadroom;
        uint16 alphaBps;
        uint16 cutBandBps;
        uint256 supply; // S
    }

    /// TODO(params): maxHeadroom in whole tokens. F1 and F2 use 500; the real value is "about $25M at launch
    /// prices, set per asset".
    uint64 internal constant MAX_HEADROOM = 500;

    // Derived values of F1: Lmin = 20, L = 100, raise bound 1,100, lo = 1,100, hi = 1,110.
    uint256 internal constant F1_DEBT = 1000;
    uint256 internal constant F1_L = 100;
    uint256 internal constant F1_LMIN = 20;
    uint256 internal constant F1_RAISE_BOUND = 1100;
    uint256 internal constant F1_CUT_FLOOR = 1100;
    uint256 internal constant F1_CUT_TRIGGER = 1110;
    uint256 internal constant F1_MAX_CAP = 10_000;
    uint256 internal constant F1_SUPPLY = 5000;

    // Derived values of F2: L = 500 (at maxHeadroom), raise bound 10,500.
    uint256 internal constant F2_DEBT = 10_000;
    uint256 internal constant F2_L = 500;
    uint256 internal constant F2_RAISE_BOUND = 10_500;

    /// @dev F1: D = 1,000, alphaBps 1000, maxHeadroom 500, cutBandBps 1000, C-bar = 10,000, S = 5,000.
    function _f1() internal pure returns (Fixture memory f) {
        f = Fixture({
            debt: F1_DEBT,
            maxCap: uint64(F1_MAX_CAP),
            maxHeadroom: MAX_HEADROOM,
            alphaBps: ALPHA_BPS,
            cutBandBps: CUT_CUT_BAND_BPS,
            supply: F1_SUPPLY
        });
    }

    /// @dev F2: D = 10,000, other values as F1. L = 500 (at maxHeadroom), raise bound 10,500.
    function _f2() internal pure returns (Fixture memory f) {
        f = _f1();
        f.debt = F2_DEBT;
    }

    function _rateLimitConfigOf(Fixture memory f) internal pure returns (IRvm.RateLimitConfig memory e) {
        e = IRvm.RateLimitConfig({
            maxCap: f.maxCap, maxHeadroom: f.maxHeadroom, alphaBps: f.alphaBps, cutBandBps: f.cutBandBps
        });
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MOCK AAVE
    // ═══════════════════════════════════════════════════════════════════════════

    MockPoolV3 internal pool;
    MockRiskSteward internal steward;
    MockERC20 internal weth; // 18 decimals
    MockERC20 internal usdc; // 6 decimals
    MockERC20 internal wbtc; // 8 decimals

    function setUp() public virtual {
        pool = new MockPoolV3();
        steward = new MockRiskSteward(riskCouncil, pool);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        wbtc = new MockERC20("Wrapped BTC", "WBTC", 8);

        // Reserves start uncapped with no debt. Tests apply a fixture with `_applyFixture`.
        pool.listReserve(address(weth), 18, 0, 0);
        pool.listReserve(address(usdc), 6, 0, 0);
        pool.listReserve(address(wbtc), 8, 0, 0);
    }

    /// @notice Whole tokens to the smallest unit of `asset`.
    function _wei(address asset, uint256 tokens) internal view returns (uint256) {
        return tokens * 10 ** MockERC20(asset).decimals();
    }

    /// @notice Put a fixture on a reserve: total debt D (exact at index 1 ray), supply cap S, and the live
    ///         borrow cap `cap` (whole tokens, 0 = uncapped).
    function _applyFixture(address asset, Fixture memory f, uint256 cap) internal {
        pool.setTotalDebt(asset, _wei(asset, f.debt));
        pool.setSupplyCap(asset, f.supply);
        pool.setBorrowCap(asset, cap);
    }

    /// @notice Set total debt to `tokens` whole tokens plus `extraUnits` smallest units (to test rounding up).
    function _setDebt(address asset, uint256 tokens, uint256 extraUnits) internal {
        pool.setTotalDebt(asset, _wei(asset, tokens) + extraUnits);
    }

    function _liveBorrowCap(address asset) internal view returns (uint256 borrowCap) {
        (borrowCap,) = pool.getReserveCaps(asset);
    }

    /// @notice Run the test as a Safe: put MockSafe's code at `riskCouncil`, so it can delegatecall and call.
    ///         Storage of the address is empty (nonce 0).
    function _etchSafeAtRiskCouncil() internal {
        vm.etch(riskCouncil, address(new MockSafe()).code);
    }
}
