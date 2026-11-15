// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IPool } from "aave-v3-origin/src/contracts/interfaces/IPool.sol";
import { DataTypes } from "aave-v3-origin/src/contracts/protocol/libraries/types/DataTypes.sol";
import {
    ReserveConfiguration
} from "aave-v3-origin/src/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {
    IAaveV3ConfigEngine as IEngine
} from "aave-v3-origin/src/contracts/extensions/v3-config-engine/IAaveV3ConfigEngine.sol";
import { EngineFlags } from "aave-v3-origin/src/contracts/extensions/v3-config-engine/EngineFlags.sol";
import { ShadowPool } from "../../src/staging/ShadowPool.sol";
import { MockPoolV3, MockVariableDebtToken } from "../caps-oracle/mocks/MockPoolV3.sol";

/// @dev Writes caps the way AaveBorrowCapAgent does: delegatecall into `agentContext` with `updateCaps`. Its two
///      storage slots let the tests prove the delegatecall writes nothing into the agent.
contract MockDelegatingAgent {
    uint256 public marker = 7;
    address public other = address(0xBEEF);

    function inject(address target, IEngine.CapsUpdate[] memory updates) external {
        Address.functionDelegateCall(target, abi.encodeWithSelector(IEngine.updateCaps.selector, updates));
    }
}

contract ShadowPoolTest is Test {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    event ShadowBorrowCapSet(address indexed asset, uint256 oldCap, uint256 newCap, address indexed writer);
    event WriterSet(address indexed writer, bool allowed);

    uint256 internal constant REAL_BORROW_CAP = 1000;
    uint256 internal constant REAL_SUPPLY_CAP = 5000;

    address internal owner = makeAddr("owner");
    address internal asset = makeAddr("asset");
    address internal other = makeAddr("otherAsset");

    MockPoolV3 internal real;
    MockVariableDebtToken internal debtToken;
    ShadowPool internal shadow;
    MockDelegatingAgent internal agent;

    function setUp() public {
        real = new MockPoolV3();
        debtToken = real.listReserve(asset, 6, REAL_BORROW_CAP, REAL_SUPPLY_CAP);
        real.listReserve(other, 18, 50, 0);
        shadow = new ShadowPool(IPool(address(real)), owner);
        agent = new MockDelegatingAgent();
        vm.prank(owner);
        shadow.setWriter(address(agent), true);
    }

    // ─── construction
    // ───────────────────────────────────────────────────────

    function test_constructor_revertsOnZeroPool() public {
        vm.expectRevert(ShadowPool.ZeroAddress.selector);
        new ShadowPool(IPool(address(0)), owner);
    }

    function test_constructor_revertsOnZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new ShadowPool(IPool(address(real)), address(0));
    }

    // ─── before any write: Aave's cap
    // ───────────────────────────────────────

    function test_beforeAnyWrite_returnsTheRealConfiguration() public view {
        assertEq(shadow.getConfiguration(asset).data, real.getConfiguration(asset).data);
        assertEq(shadow.borrowCap(asset), REAL_BORROW_CAP);
        assertEq(shadow.realBorrowCap(asset), REAL_BORROW_CAP);
        assertFalse(shadow.hasShadowCap(asset));
    }

    function test_beforeAnyWrite_followsARealCapChange() public {
        real.setBorrowCap(asset, 1234);
        assertEq(shadow.getConfiguration(asset).getBorrowCap(), 1234);
        assertEq(shadow.borrowCap(asset), 1234);
    }

    // ─── setBorrowCap
    // ───────────────────────────────────────────────────────

    function test_setBorrowCap_revertsForANonWriter() public {
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ShadowPool.NotWriter.selector, stranger));
        shadow.setBorrowCap(asset, 900);
    }

    function test_setBorrowCap_revertsForTheOwner() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ShadowPool.NotWriter.selector, owner));
        shadow.setBorrowCap(asset, 900);
    }

    function test_setBorrowCap_swapsOnlyTheBorrowCap() public {
        vm.expectEmit(address(shadow));
        emit ShadowBorrowCapSet(asset, REAL_BORROW_CAP, 900, address(agent));
        vm.prank(address(agent));
        shadow.setBorrowCap(asset, 900);

        DataTypes.ReserveConfigurationMap memory expected = real.getConfiguration(asset);
        expected.setBorrowCap(900);
        assertEq(shadow.getConfiguration(asset).data, expected.data);
        assertEq(shadow.getConfiguration(asset).getSupplyCap(), REAL_SUPPLY_CAP);
        assertTrue(shadow.hasShadowCap(asset));
        // The real Pool and the other reserve are untouched.
        assertEq(real.getConfiguration(asset).getBorrowCap(), REAL_BORROW_CAP);
        assertEq(shadow.getConfiguration(other).data, real.getConfiguration(other).data);
    }

    function test_setBorrowCap_stopsFollowingTheRealCap() public {
        vm.prank(address(agent));
        shadow.setBorrowCap(asset, 900);
        real.setBorrowCap(asset, 1234);
        assertEq(shadow.borrowCap(asset), 900);
        assertEq(shadow.realBorrowCap(asset), 1234);
    }

    function test_setBorrowCap_secondWriteReportsOurCapAsOld() public {
        vm.startPrank(address(agent));
        shadow.setBorrowCap(asset, 900);
        vm.expectEmit(address(shadow));
        emit ShadowBorrowCapSet(asset, 900, 950, address(agent));
        shadow.setBorrowCap(asset, 950);
        vm.stopPrank();
    }

    function test_setBorrowCap_zeroIsAStoredCap() public {
        vm.prank(address(agent));
        shadow.setBorrowCap(asset, 0);
        assertTrue(shadow.hasShadowCap(asset));
        assertEq(shadow.getConfiguration(asset).getBorrowCap(), 0);
    }

    function test_setBorrowCap_revertsAboveAavesMaximum() public {
        uint256 max = ReserveConfiguration.MAX_VALID_BORROW_CAP;
        vm.startPrank(address(agent));
        shadow.setBorrowCap(asset, max);
        vm.expectRevert(abi.encodeWithSelector(ShadowPool.BorrowCapTooHigh.selector, max + 1));
        shadow.setBorrowCap(asset, max + 1);
        vm.stopPrank();
        assertEq(shadow.borrowCap(asset), max);
    }

    function testFuzz_setBorrowCap_keepsEveryOtherBit(uint256 cap) public {
        cap = bound(cap, 0, ReserveConfiguration.MAX_VALID_BORROW_CAP);
        vm.prank(address(agent));
        shadow.setBorrowCap(asset, cap);
        DataTypes.ReserveConfigurationMap memory expected = real.getConfiguration(asset);
        expected.setBorrowCap(cap);
        assertEq(shadow.getConfiguration(asset).data, expected.data);
    }

    // ─── setWriter
    // ──────────────────────────────────────────────────────────

    function test_setWriter_onlyOwner() public {
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        shadow.setWriter(stranger, true);
    }

    function test_setWriter_revertsOnZero() public {
        vm.prank(owner);
        vm.expectRevert(ShadowPool.ZeroAddress.selector);
        shadow.setWriter(address(0), true);
    }

    function test_setWriter_removesAWriter() public {
        vm.expectEmit(address(shadow));
        emit WriterSet(address(agent), false);
        vm.prank(owner);
        shadow.setWriter(address(agent), false);
        assertFalse(shadow.isWriter(address(agent)));
        vm.prank(address(agent));
        vm.expectRevert(abi.encodeWithSelector(ShadowPool.NotWriter.selector, address(agent)));
        shadow.setBorrowCap(asset, 900);
    }

    // ─── updateCaps: the agent's delegatecall
    // ───────────────────────────────

    function test_updateCaps_revertsWhenCalledDirectly() public {
        vm.expectRevert(ShadowPool.OnlyDelegateCall.selector);
        shadow.updateCaps(_one(asset, EngineFlags.KEEP_CURRENT, 900));
    }

    function test_updateCaps_byDelegatecall_writesTheCapAsTheAgent() public {
        vm.expectEmit(address(shadow));
        emit ShadowBorrowCapSet(asset, REAL_BORROW_CAP, 900, address(agent));
        agent.inject(address(shadow), _one(asset, EngineFlags.KEEP_CURRENT, 900));

        assertEq(shadow.borrowCap(asset), 900);
        // Supply cap ignored, agent storage untouched.
        assertEq(shadow.getConfiguration(asset).getSupplyCap(), REAL_SUPPLY_CAP);
        assertEq(agent.marker(), 7);
        assertEq(agent.other(), address(0xBEEF));
    }

    function test_updateCaps_byDelegatecall_ignoresTheSupplyCap() public {
        agent.inject(address(shadow), _one(asset, 1, 900));
        assertEq(shadow.getConfiguration(asset).getSupplyCap(), REAL_SUPPLY_CAP);
    }

    function test_updateCaps_byDelegatecall_skipsKeepCurrent() public {
        agent.inject(address(shadow), _one(asset, EngineFlags.KEEP_CURRENT, EngineFlags.KEEP_CURRENT));
        assertFalse(shadow.hasShadowCap(asset));
    }

    function test_updateCaps_byDelegatecall_appliesEveryEntry() public {
        IEngine.CapsUpdate[] memory updates = new IEngine.CapsUpdate[](2);
        updates[0] = IEngine.CapsUpdate({ asset: asset, supplyCap: EngineFlags.KEEP_CURRENT, borrowCap: 900 });
        updates[1] = IEngine.CapsUpdate({ asset: other, supplyCap: EngineFlags.KEEP_CURRENT, borrowCap: 40 });
        agent.inject(address(shadow), updates);
        assertEq(shadow.borrowCap(asset), 900);
        assertEq(shadow.borrowCap(other), 40);
    }

    function test_updateCaps_byDelegatecall_revertsForAnAgentThatIsNotAWriter() public {
        MockDelegatingAgent stranger = new MockDelegatingAgent();
        vm.expectRevert(abi.encodeWithSelector(ShadowPool.NotWriter.selector, address(stranger)));
        stranger.inject(address(shadow), _one(asset, EngineFlags.KEEP_CURRENT, 900));
    }

    // ─── fallback: every other call goes to the real Pool, read only ────────

    function test_fallback_forwardsReads() public view {
        IPool pool = IPool(address(shadow));
        address[] memory list = pool.getReservesList();
        assertEq(list.length, 2);
        assertEq(list[0], asset);
        assertEq(pool.getReserveData(asset).variableDebtTokenAddress, address(debtToken));
        assertEq(pool.getReserveNormalizedVariableDebt(asset), real.getReserveNormalizedVariableDebt(asset));
    }

    function test_fallback_bubblesARevert() public {
        vm.expectRevert(MockPoolV3.InvalidInterestRateMode.selector);
        IPool(address(shadow)).borrow(asset, 1, 1, 0, address(this));
    }

    function test_fallback_cannotChangeRealPoolState() public {
        vm.expectRevert();
        IPool(address(shadow)).borrow(asset, 1, 2, 0, address(this));
        assertEq(debtToken.totalSupply(), 0);
    }

    /// @dev No function of ours may answer a Pool selector other than getConfiguration, which is the one we mean to
    ///      override. A clash would silently replace a real Pool read.
    function test_noSelectorClashesWithThePool() public view {
        string[] memory poolSigs =
            vm.parseJsonKeys(vm.readFile(_artifact("IPool.sol/IPool.json")), ".methodIdentifiers");
        string[] memory ours =
            vm.parseJsonKeys(vm.readFile(_artifact("ShadowPool.sol/ShadowPool.json")), ".methodIdentifiers");
        assertGt(poolSigs.length, 50);
        bool overridesGetConfiguration;
        for (uint256 i; i < ours.length; ++i) {
            bytes4 selector = bytes4(keccak256(bytes(ours[i])));
            if (selector == IPool.getConfiguration.selector) {
                overridesGetConfiguration = true;
                continue;
            }
            for (uint256 j; j < poolSigs.length; ++j) {
                assertTrue(selector != bytes4(keccak256(bytes(poolSigs[j]))), ours[i]);
            }
        }
        assertTrue(overridesGetConfiguration);
    }

    // ─── helpers
    // ────────────────────────────────────────────────────────────

    function _one(
        address a,
        uint256 supplyCap,
        uint256 borrowCap
    )
        internal
        pure
        returns (IEngine.CapsUpdate[] memory u)
    {
        u = new IEngine.CapsUpdate[](1);
        u[0] = IEngine.CapsUpdate({ asset: a, supplyCap: supplyCap, borrowCap: borrowCap });
    }

    function _artifact(string memory path) internal view returns (string memory) {
        // The fork profile builds into out/prague (foundry.toml).
        bool fork = keccak256(bytes(vm.envOr("FOUNDRY_PROFILE", string("default")))) == keccak256("fork");
        return string.concat(vm.projectRoot(), fork ? "/out/prague/" : "/out/", path);
    }
}
