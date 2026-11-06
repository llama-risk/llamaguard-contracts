// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IRiskOracle } from "chaos-agents/contracts/dependencies/IRiskOracle.sol";
import { AgentHub } from "chaos-agents/contracts/AgentHub.sol";
import { IAgentHub } from "chaos-agents/interfaces/IAgentHub.sol";
import { IAgentConfigurator } from "chaos-agents/interfaces/IAgentConfigurator.sol";
import { CapsTestBase } from "./CapsTestBase.sol";
import { MockCapsRvm } from "./mocks/MockCapsRvm.sol";
import { MockCutAgent } from "./mocks/MockCutAgent.sol";
import { CapsReducerOracle } from "../../src/caps-oracle/CapsReducerOracle.sol";
import { ICapsReducerOracle } from "../../src/caps-oracle/interfaces/ICapsReducerOracle.sol";
import { ICapsRangeValidationModule as IRvm } from "../../src/caps-oracle/interfaces/ICapsRangeValidationModule.sol";

/// @notice Unit tests of CapsReducerOracle against MockCapsRvm (CAP-INV-03, CAP-INV-10, CAP-ACL-11,
///         CAP-ACL-15, CAP-ACL-22) and against a local AgentHub (CAP-ST-16).
contract CapsReducerOracleTest is CapsTestBase {
    MockCapsRvm internal rvm;
    CapsReducerOracle internal oracle; // serves BORROW and SUPPLY

    // F1 cut example (CAP-INV-03): cap 1,200 cuts to lo = 1,100. Cap 1,110 (= hi) is not due.
    uint256 internal constant F1_CUT_FROM = 1200;

    function setUp() public virtual override {
        super.setUp();
        rvm = new MockCapsRvm();
        oracle = new CapsReducerOracle(IRvm(address(rvm)));
    }

    function _read(
        string memory updateType,
        address asset
    )
        internal
        view
        returns (IRiskOracle.RiskParameterUpdate memory)
    {
        // AgentHub calls the oracle through IRiskOracle, so the tests do the same.
        return IRiskOracle(address(oracle)).getLatestUpdateByParameterAndMarket(updateType, asset);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CAP-INV-03 reducer returns the RVM cut
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CAP_INV_03_reducer_F1_returnsPreviewCut() public {
        rvm.setCut(address(weth), IRvm.CapKind.BORROW, true, F1_CUT_FROM, F1_CUT_FLOOR);
        vm.roll(100);
        vm.warp(1_800_000_000);

        IRiskOracle.RiskParameterUpdate memory u = _read(BORROW_UPDATE_TYPE, address(weth));

        assertEq(abi.decode(u.newValue, (uint256)), F1_CUT_FLOOR, "newValue = previewCut.newCap");
        assertEq(abi.decode(u.previousValue, (uint256)), F1_CUT_FROM, "previousValue = previewCut.currentCap");
        assertEq(u.newValue.length, 32, "agent _decodeToUint needs <= 32 bytes");
        assertEq(u.timestamp, 1_800_000_000, "timestamp = block.timestamp");
        assertEq(u.updateId, 100, "updateId = block.number");
        assertEq(u.market, address(weth), "market = asset");
        assertEq(u.updateType, BORROW_UPDATE_TYPE, "updateType echoed");
        assertEq(bytes(u.referenceId).length, 0, "referenceId empty");
        assertEq(u.additionalData.length, 0, "additionalData empty");
    }

    function test_CAP_INV_03_reducer_F1_atBandTop_revertsNoCutDue() public {
        // The RVM reports no cut at cap 1,110 (= hi). The oracle reverts, so AgentHub skips the asset.
        rvm.setCut(address(weth), IRvm.CapKind.BORROW, false, F1_CUT_TRIGGER, F1_CUT_FLOOR);
        vm.expectRevert(abi.encodeWithSelector(ICapsReducerOracle.NoCutDue.selector, address(weth)));
        _read(BORROW_UPDATE_TYPE, address(weth));
    }

    function test_CAP_INV_03_reducer_noCutForKind_revertsNoCutDue() public {
        // BORROW cut due, SUPPLY not: the supply update type asks the RVM on the SUPPLY key and reverts.
        rvm.setCut(address(weth), IRvm.CapKind.BORROW, true, F1_CUT_FROM, F1_CUT_FLOOR);
        vm.expectRevert(abi.encodeWithSelector(ICapsReducerOracle.NoCutDue.selector, address(weth)));
        oracle.getLatestUpdateByParameterAndMarket(SUPPLY_UPDATE_TYPE, address(weth));
    }

    function test_CAP_INV_03_reducer_borrowUpdateType_borrowCut() public {
        rvm.setCut(address(weth), IRvm.CapKind.BORROW, true, F1_CUT_FROM, F1_CUT_FLOOR);
        rvm.setCut(address(weth), IRvm.CapKind.SUPPLY, true, 9000, 6000);
        IRiskOracle.RiskParameterUpdate memory u = _read(BORROW_UPDATE_TYPE, address(weth));
        assertEq(abi.decode(u.newValue, (uint256)), F1_CUT_FLOOR, "BORROW cut");
        assertEq(abi.decode(u.previousValue, (uint256)), F1_CUT_FROM);
        assertEq(u.updateType, BORROW_UPDATE_TYPE, "updateType echoed");
    }

    function test_CAP_INV_03_reducer_supplyUpdateType_supplyCut() public {
        rvm.setCut(address(weth), IRvm.CapKind.BORROW, true, F1_CUT_FROM, F1_CUT_FLOOR);
        rvm.setCut(address(weth), IRvm.CapKind.SUPPLY, true, 9000, 6000);
        IRiskOracle.RiskParameterUpdate memory u = _read(SUPPLY_UPDATE_TYPE, address(weth));
        assertEq(abi.decode(u.newValue, (uint256)), 6000, "SUPPLY cut");
        assertEq(abi.decode(u.previousValue, (uint256)), 9000);
        assertEq(u.updateType, SUPPLY_UPDATE_TYPE, "updateType echoed");
    }

    function test_CAP_INV_03_reducer_unknownUpdateType_reverts() public {
        rvm.setCut(address(weth), IRvm.CapKind.BORROW, true, F1_CUT_FROM, F1_CUT_FLOOR);
        rvm.setCut(address(weth), IRvm.CapKind.SUPPLY, true, 9000, 6000);
        string[3] memory types = ["LtvUpdate_Core", "BorrowCapUpdate_Prime", "borrowcapupdate_core"];
        for (uint256 i = 0; i < types.length; ++i) {
            vm.expectRevert(abi.encodeWithSelector(ICapsReducerOracle.UnknownUpdateType.selector, types[i]));
            _read(types[i], address(weth));
        }
    }

    function test_CAP_INV_03_reducer_emptyUpdateType_reverts() public {
        rvm.setCut(address(weth), IRvm.CapKind.BORROW, true, F1_CUT_FROM, F1_CUT_FLOOR);
        vm.expectRevert(abi.encodeWithSelector(ICapsReducerOracle.UnknownUpdateType.selector, ""));
        _read("", address(weth));
    }

    function test_CAP_INV_03_reducer_fuzz_unknownUpdateType_reverts(string memory updateType) public {
        bytes32 h = keccak256(bytes(updateType));
        vm.assume(h != keccak256(bytes(BORROW_UPDATE_TYPE)) && h != keccak256(bytes(SUPPLY_UPDATE_TYPE)));
        rvm.setCut(address(weth), IRvm.CapKind.BORROW, true, F1_CUT_FROM, F1_CUT_FLOOR);
        vm.expectRevert(abi.encodeWithSelector(ICapsReducerOracle.UnknownUpdateType.selector, updateType));
        _read(updateType, address(weth));
    }

    function test_CAP_INV_03_reducer_hashesFromRvm() public {
        // The oracle matches against the RVM's update types, read once at construction.
        MockCapsRvm primeRvm = new MockCapsRvm();
        primeRvm.setUpdateTypeHashes(keccak256("BorrowCapUpdate_Prime"), keccak256("SupplyCapUpdate_Prime"));
        CapsReducerOracle primeOracle = new CapsReducerOracle(IRvm(address(primeRvm)));
        assertEq(primeOracle.BORROW_UPDATE_TYPE_HASH(), keccak256("BorrowCapUpdate_Prime"));
        assertEq(primeOracle.SUPPLY_UPDATE_TYPE_HASH(), keccak256("SupplyCapUpdate_Prime"));
        primeRvm.setCut(address(weth), IRvm.CapKind.SUPPLY, true, 9000, 6000);

        IRiskOracle.RiskParameterUpdate memory u =
            primeOracle.getLatestUpdateByParameterAndMarket("SupplyCapUpdate_Prime", address(weth));
        assertEq(abi.decode(u.newValue, (uint256)), 6000);
        vm.expectRevert(abi.encodeWithSelector(ICapsReducerOracle.UnknownUpdateType.selector, SUPPLY_UPDATE_TYPE));
        primeOracle.getLatestUpdateByParameterAndMarket(SUPPLY_UPDATE_TYPE, address(weth));
    }

    function test_CAP_INV_03_reducer_asksRvmWithAssetAndKind() public {
        rvm.setCut(address(weth), IRvm.CapKind.SUPPLY, true, 9000, 6000);
        vm.expectCall(address(rvm), abi.encodeCall(IRvm.previewCut, (address(weth), IRvm.CapKind.SUPPLY)));
        oracle.getLatestUpdateByParameterAndMarket(SUPPLY_UPDATE_TYPE, address(weth));
    }

    function test_CAP_INV_03_reducer_oneRvmCallPerRead() public {
        // One keyed previewCut per read, and no other call to the RVM.
        rvm.setCut(address(weth), IRvm.CapKind.BORROW, true, F1_CUT_FROM, F1_CUT_FLOOR);
        vm.expectCall(address(rvm), abi.encodeCall(IRvm.previewCut, (address(weth), IRvm.CapKind.BORROW)), 1);
        vm.expectCall(address(rvm), bytes(""), 1);
        _read(BORROW_UPDATE_TYPE, address(weth));
    }

    function test_CAP_INV_03_reducer_returnsCutOfItsKind() public {
        // One oracle per Pool: the update type selects the kind on the shared RVM.
        rvm.setCut(address(weth), IRvm.CapKind.BORROW, true, F1_CUT_FROM, F1_CUT_FLOOR);
        rvm.setCut(address(weth), IRvm.CapKind.SUPPLY, true, 9000, 6000);

        assertEq(abi.decode(_read(BORROW_UPDATE_TYPE, address(weth)).newValue, (uint256)), F1_CUT_FLOOR);
        IRiskOracle.RiskParameterUpdate memory s =
            oracle.getLatestUpdateByParameterAndMarket(SUPPLY_UPDATE_TYPE, address(weth));
        assertEq(abi.decode(s.newValue, (uint256)), 6000);
        assertEq(abi.decode(s.previousValue, (uint256)), 9000);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CAP-ACL-22 one reducer per RVM (one RVM per Pool)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CAP_ACL_22_twoPools_ownReducerEach() public {
        // Core and Prime each have their own RVM and reducer, so the same AgentHub call returns each Pool's cut.
        MockCapsRvm primeRvm = new MockCapsRvm();
        CapsReducerOracle primeOracle = new CapsReducerOracle(IRvm(address(primeRvm)));
        rvm.setCut(address(weth), IRvm.CapKind.BORROW, true, F1_CUT_FROM, F1_CUT_FLOOR);
        primeRvm.setCut(address(weth), IRvm.CapKind.BORROW, true, 3000, 2200);

        IRiskOracle.RiskParameterUpdate memory core = _read(BORROW_UPDATE_TYPE, address(weth));
        IRiskOracle.RiskParameterUpdate memory p =
            IRiskOracle(address(primeOracle)).getLatestUpdateByParameterAndMarket(BORROW_UPDATE_TYPE, address(weth));
        assertEq(abi.decode(core.newValue, (uint256)), F1_CUT_FLOOR, "Core cut");
        assertEq(abi.decode(core.previousValue, (uint256)), F1_CUT_FROM);
        assertEq(abi.decode(p.newValue, (uint256)), 2200, "Prime cut");
        assertEq(abi.decode(p.previousValue, (uint256)), 3000);

        // No Prime cut due leaves Core untouched.
        primeRvm.setCut(address(weth), IRvm.CapKind.BORROW, false, 2210, 2200);
        vm.expectRevert(abi.encodeWithSelector(ICapsReducerOracle.NoCutDue.selector, address(weth)));
        primeOracle.getLatestUpdateByParameterAndMarket(BORROW_UPDATE_TYPE, address(weth));
        assertEq(abi.decode(_read(BORROW_UPDATE_TYPE, address(weth)).newValue, (uint256)), F1_CUT_FLOOR);
    }

    function test_CAP_INV_03_reducer_fuzz_matchesPreviewCut(
        bool due,
        uint256 currentCap,
        uint256 newCap,
        address asset,
        uint64 blockNumber
    )
        public
    {
        vm.roll(blockNumber);
        rvm.setCut(asset, IRvm.CapKind.BORROW, due, currentCap, newCap);
        (bool pDue, uint256 pCur, uint256 pNew) = rvm.previewCut(asset, IRvm.CapKind.BORROW);

        if (!pDue) {
            vm.expectRevert(abi.encodeWithSelector(ICapsReducerOracle.NoCutDue.selector, asset));
            _read(BORROW_UPDATE_TYPE, asset);
            return;
        }
        IRiskOracle.RiskParameterUpdate memory u = _read(BORROW_UPDATE_TYPE, asset);
        assertEq(abi.decode(u.newValue, (uint256)), pNew);
        assertEq(abi.decode(u.previousValue, (uint256)), pCur);
        assertEq(u.updateId, blockNumber);
        assertEq(u.market, asset);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CAP-INV-10 check path is read-only (oracle part)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CAP_INV_10_reducerRead_writesNoStorage() public {
        rvm.setCut(address(weth), IRvm.CapKind.BORROW, true, F1_CUT_FROM, F1_CUT_FLOOR);

        vm.record();
        _read(BORROW_UPDATE_TYPE, address(weth));
        (bytes32[] memory oracleReads, bytes32[] memory oracleWrites) = vm.accesses(address(oracle));
        (, bytes32[] memory rvmWrites) = vm.accesses(address(rvm));

        assertEq(oracleReads.length, 0, "oracle reads no storage of its own");
        assertEq(oracleWrites.length, 0, "oracle writes no storage");
        assertEq(rvmWrites.length, 0, "oracle read writes no RVM storage");
    }

    function test_CAP_INV_10_reducerRead_succeedsAsStaticcall() public {
        rvm.setCut(address(weth), IRvm.CapKind.BORROW, true, F1_CUT_FROM, F1_CUT_FLOOR);
        bytes memory data = abi.encodeCall(
            ICapsReducerOracle.getLatestUpdateByParameterAndMarket, (BORROW_UPDATE_TYPE, address(weth))
        );
        (bool ok,) = address(oracle).staticcall(data);
        assertTrue(ok, "a STATICCALL frame forbids any state change");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CAP-ACL-11 reducer link immutable
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CAP_ACL_11_reducer_rvmFixedAtConstruction() public view {
        assertEq(address(oracle.RVM()), address(rvm));
        assertEq(oracle.BORROW_UPDATE_TYPE_HASH(), keccak256(bytes(BORROW_UPDATE_TYPE)));
        assertEq(oracle.SUPPLY_UPDATE_TYPE_HASH(), keccak256(bytes(SUPPLY_UPDATE_TYPE)));
        // No storage at all: the RVM link and the update type hashes live in the bytecode.
        for (uint256 slot = 0; slot < 8; slot++) {
            assertEq(vm.load(address(oracle), bytes32(slot)), bytes32(0));
        }
    }

    function test_CAP_ACL_11_reducer_zeroRvm_reverts() public {
        vm.expectRevert(CapsReducerOracle.ZeroAddress.selector);
        new CapsReducerOracle(IRvm(address(0)));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CAP-ACL-15 views are open (oracle part)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CAP_ACL_15_reducerRead_anyCaller(address caller) public {
        rvm.setCut(address(weth), IRvm.CapKind.BORROW, true, F1_CUT_FROM, F1_CUT_FLOOR);
        vm.prank(caller);
        IRiskOracle.RiskParameterUpdate memory u = _read(BORROW_UPDATE_TYPE, address(weth));
        assertEq(abi.decode(u.newValue, (uint256)), F1_CUT_FLOOR);
    }
}

/// @notice CAP-ST-16 with the real AgentHub behind an ERC1967 proxy, a stand-in cut agent and the mock RVM.
/// @dev A fork version is planned. This local version runs the same AgentHub code
///      (`_validateBasics` updateId check, `_setUpdateInjected`) without a fork.
contract CapsReducerOracleAgentHubTest is CapsTestBase {
    AgentHub internal hub;
    MockCapsRvm internal rvm;
    CapsReducerOracle internal oracle;
    MockCutAgent internal agent;
    uint256 internal cutId;

    function setUp() public virtual override {
        super.setUp();
        AgentHub impl = new AgentHub();
        hub = AgentHub(address(new ERC1967Proxy(address(impl), abi.encodeCall(AgentHub.initialize, (governance)))));
        rvm = new MockCapsRvm();
        oracle = new CapsReducerOracle(IRvm(address(rvm)));
        agent = new MockCutAgent(address(hub));

        address[] memory markets = new address[](1);
        markets[0] = address(weth);
        IAgentConfigurator.AgentRegistrationInput memory input = IAgentConfigurator.AgentRegistrationInput({
            admin: agentAdmin,
            riskOracle: address(oracle),
            isAgentEnabled: true,
            isAgentPermissioned: false, // cut agent is permissionless
            isMarketsFromAgentEnabled: false,
            agentAddress: address(agent),
            expirationPeriod: EXPIRATION_PERIOD,
            minimumDelay: 0, // cut agent minimumDelay 0
            updateType: BORROW_UPDATE_TYPE,
            agentContext: "",
            allowedMarkets: markets,
            restrictedMarkets: new address[](0),
            permissionedSenders: new address[](0)
        });
        vm.prank(governance);
        cutId = hub.registerAgent(input);

        rvm.setCut(address(weth), IRvm.CapKind.BORROW, true, 1200, F1_CUT_FLOOR);
    }

    function _ids() internal view returns (uint256[] memory ids) {
        ids = new uint256[](1);
        ids[0] = cutId;
    }

    function test_CAP_ST_16_cut_twiceSameBlock_reverts() public {
        vm.roll(100);
        (bool ok, IAgentHub.ActionData[] memory actions) = hub.check(_ids());
        assertTrue(ok, "cut due at block 100");

        vm.prank(attacker); // permissionless keeper
        hub.execute(actions);
        assertEq(agent.injectCount(), 1);
        assertEq(agent.lastNewCap(), F1_CUT_FLOOR);
        assertEq(agent.lastUpdateId(), 100);

        // Same block: the oracle serves updateId 100 again and AgentHub rejects id <= last injected id.
        (ok,) = hub.check(_ids());
        assertFalse(ok, "check reports nothing in the same block");
        vm.expectRevert(IAgentHub.NoActionCanBePerformed.selector);
        hub.execute(actions);
        assertEq(agent.injectCount(), 1);

        // Next block: a new updateId, so a further cut can land.
        vm.roll(101);
        hub.execute(actions);
        assertEq(agent.injectCount(), 2);
        assertEq(agent.lastUpdateId(), 101);
    }

    function test_CAP_ST_16_noCutDue_hubSkipsAsset() public {
        rvm.setCut(address(weth), IRvm.CapKind.BORROW, false, 1110, F1_CUT_FLOOR);
        (bool ok,) = hub.check(_ids());
        assertFalse(ok, "oracle revert makes AgentHub skip the asset");
        IAgentHub.ActionData[] memory actions = new IAgentHub.ActionData[](1);
        actions[0].agentId = cutId;
        actions[0].markets = new address[](1);
        actions[0].markets[0] = address(weth);
        vm.expectRevert(IAgentHub.NoActionCanBePerformed.selector);
        hub.execute(actions);
    }
}

/// @notice Handler for the reducer invariants: it moves the mock RVM state and the block around.
contract ReducerHandler is Test {
    MockCapsRvm internal rvm;
    address[] public assets;

    constructor(MockCapsRvm rvm_, address[] memory assets_) {
        rvm = rvm_;
        assets = assets_;
    }

    function setCut(uint256 assetSeed, bool due, uint256 currentCap, uint256 newCap) external {
        rvm.setCut(assets[assetSeed % assets.length], IRvm.CapKind.BORROW, due, currentCap, newCap);
    }

    function nextBlock(uint8 blocks, uint16 secs) external {
        vm.roll(block.number + blocks);
        vm.warp(block.timestamp + secs);
    }

    function assetCount() external view returns (uint256) {
        return assets.length;
    }
}

/// @notice Invariants CAP-INV-03 and CAP-ACL-11 over random RVM states and blocks.
contract CapsReducerOracleInvariantTest is CapsTestBase {
    MockCapsRvm internal rvm;
    CapsReducerOracle internal oracle;
    ReducerHandler internal handler;
    address internal initialRvm;

    function setUp() public virtual override {
        super.setUp();
        rvm = new MockCapsRvm();
        oracle = new CapsReducerOracle(IRvm(address(rvm)));
        initialRvm = address(rvm);

        address[] memory assets = new address[](3);
        assets[0] = address(weth);
        assets[1] = address(usdc);
        assets[2] = address(wbtc);
        handler = new ReducerHandler(rvm, assets);

        targetContract(address(handler));
        targetContract(address(oracle)); // any call to the oracle itself must not move its link
    }

    function invariant_CAP_INV_03_reducerReturnsPreviewCut() public view {
        for (uint256 i = 0; i < handler.assetCount(); i++) {
            address asset = handler.assets(i);
            (bool due, uint256 cur, uint256 newCap) = rvm.previewCut(asset, IRvm.CapKind.BORROW);
            try IRiskOracle(address(oracle)).getLatestUpdateByParameterAndMarket(BORROW_UPDATE_TYPE, asset) returns (
                IRiskOracle.RiskParameterUpdate memory u
            ) {
                assertTrue(due, "oracle returned while previewCut is not due");
                assertEq(abi.decode(u.newValue, (uint256)), newCap, "newValue != previewCut.newCap");
                assertEq(abi.decode(u.previousValue, (uint256)), cur, "previousValue != previewCut.currentCap");
                assertEq(u.updateId, block.number, "updateId != block.number");
                assertEq(u.timestamp, block.timestamp, "timestamp != block.timestamp");
                assertEq(u.market, asset, "market != asset");
            } catch (bytes memory err) {
                assertFalse(due, "oracle reverted while previewCut is due");
                assertEq(err, abi.encodeWithSelector(ICapsReducerOracle.NoCutDue.selector, asset));
            }
        }
    }

    function invariant_CAP_ACL_11_reducerLinkImmutable() public view {
        assertEq(address(oracle.RVM()), initialRvm);
    }
}
