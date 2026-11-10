// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { AgentHub } from "chaos-agents/contracts/AgentHub.sol";
import { IAgentConfigurator } from "chaos-agents/interfaces/IAgentConfigurator.sol";
import { IRangeValidationModule } from "chaos-agents/interfaces/IRangeValidationModule.sol";
import { ICapsRangeValidationModule as IRvm } from "../../src/caps-oracle/interfaces/ICapsRangeValidationModule.sol";
import { CapsRangeValidationModuleV3 } from "../../src/caps-oracle/CapsRangeValidationModuleV3.sol";
import { CapsTestBase } from "./CapsTestBase.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";

/// @title MockCapAgent
/// @notice Cap agent stand-in with the reads the RVM makes of the agent at registration: `POOL()`,
///         `RANGE_VALIDATION_MODULE()` (BaseAaveAgent.sol:15-16) and `AGENT_HUB()` (IBaseAgent.sol:20).
contract MockCapAgent {
    address public POOL;
    address public RANGE_VALIDATION_MODULE;
    address public AGENT_HUB;

    constructor(address pool, address rvm, address agentHub) {
        POOL = pool;
        RANGE_VALIDATION_MODULE = rvm;
        AGENT_HUB = agentHub;
    }
}

/// @title RvmTestBase
/// @notice Deploys CapsRangeValidationModuleV3 on the mock Pool and the real AgentHub (ERC1967 proxy, owner the
///         governance executor) with a raise and a cut BORROW agentId, the global BORROW bounds, and helpers to
///         apply a fixture and call `validate`. Agent addresses are set by agentId with `setAgentAddress`; the
///         AgentHub update type of an agentId is mocked with `_setHubUpdateType`.
abstract contract RvmTestBase is CapsTestBase {
    CapsRangeValidationModuleV3 internal rvm;
    AgentHub internal hub;
    MockCapAgent internal raiseAgent;
    MockCapAgent internal cutAgent;

    uint256 internal constant SUPPLY_RAISE_AGENT_ID = 3;
    uint256 internal constant SUPPLY_CUT_AGENT_ID = 4;

    function setUp() public virtual override {
        super.setUp();
        hub = AgentHub(
            address(new ERC1967Proxy(address(new AgentHub()), abi.encodeCall(AgentHub.initialize, (governance))))
        );
        agentHub = address(hub);
        rvm = new CapsRangeValidationModuleV3(
            governance, agentHub, address(pool), riskCouncil, BORROW_UPDATE_TYPE, SUPPLY_UPDATE_TYPE
        );

        raiseAgent = _newAgent(RAISE_AGENT_ID, BORROW_UPDATE_TYPE);
        cutAgent = _newAgent(CUT_AGENT_ID, BORROW_UPDATE_TYPE);

        vm.startPrank(governance);
        rvm.setAgent(RAISE_AGENT_ID, IRvm.Direction.RAISE);
        rvm.setAgent(CUT_AGENT_ID, IRvm.Direction.CUT);
        rvm.setBounds(IRvm.CapKind.BORROW, _globalBorrowBounds());
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SETUP HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    function _newAgent(uint256 agentId, string memory updateType) internal returns (MockCapAgent a) {
        a = new MockCapAgent(address(pool), address(rvm), agentHub);
        vm.prank(governance);
        hub.setAgentAddress(agentId, address(a));
        _setHubUpdateType(agentId, updateType);
    }

    /// @dev AgentHub sets the update type only in `registerAgent`, so tests that set agent addresses by
    ///      agentId mock `getUpdateType(agentId)`.
    function _setHubUpdateType(uint256 agentId, string memory updateType) internal {
        vm.mockCall(agentHub, abi.encodeCall(IAgentConfigurator.getUpdateType, (agentId)), abi.encode(updateType));
    }

    /// @dev Registers the SUPPLY raise and cut agentIds and the global SUPPLY bounds (same as BORROW).
    function _registerSupplyAgents() internal {
        _newAgent(SUPPLY_RAISE_AGENT_ID, SUPPLY_UPDATE_TYPE);
        _newAgent(SUPPLY_CUT_AGENT_ID, SUPPLY_UPDATE_TYPE);
        vm.startPrank(governance);
        rvm.setAgent(SUPPLY_RAISE_AGENT_ID, IRvm.Direction.RAISE);
        rvm.setAgent(SUPPLY_CUT_AGENT_ID, IRvm.Direction.CUT);
        rvm.setBounds(IRvm.CapKind.SUPPLY, _globalBorrowBounds());
        vm.stopPrank();
    }

    /// @dev Puts fixture `f` on the Pool (D, S, live cap) and writes its entry as the owner.
    function _useFixture(address asset, Fixture memory f, uint256 cap) internal {
        _applyFixture(asset, f, cap);
        _setRateLimitConfig(asset, IRvm.CapKind.BORROW, _rateLimitConfigOf(f));
    }

    function _useF1(uint256 cap) internal {
        _useFixture(address(weth), _f1(), cap);
    }

    /// @dev Owner write: any maxCap, no relative rule, no cooldown.
    function _setRateLimitConfig(address asset, IRvm.CapKind kind, IRvm.RateLimitConfig memory e) internal {
        vm.prank(governance);
        rvm.setRateLimitConfig(asset, kind, e);
    }

    /// @dev Risk Council write of the BORROW entry of `asset` with only maxCap changed.
    function _setMaxCap(address asset, uint64 maxCap) internal {
        IRvm.KeyState memory k = rvm.getKeyState(asset, IRvm.CapKind.BORROW);
        vm.prank(riskCouncil);
        rvm.setRateLimitConfig(
            asset,
            IRvm.CapKind.BORROW,
            IRvm.RateLimitConfig({
                maxCap: maxCap, maxHeadroom: k.maxHeadroom, alphaBps: k.alphaBps, cutBandBps: k.cutBandBps
            })
        );
    }

    function _setHold(address asset, IRvm.CapKind kind, uint40 until) internal {
        vm.prank(riskCouncil);
        rvm.setHold(asset, kind, until);
    }

    /// @dev Sets the SUPPLY level of `asset` to `tokens` whole tokens through a fresh aToken.
    function _setSupplied(address asset, uint256 tokens) internal {
        MockERC20 aToken = new MockERC20("aToken", "aT", MockERC20(asset).decimals());
        aToken.mint(address(this), _wei(asset, tokens));
        pool.setAToken(asset, address(aToken), 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CALL HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    function _input(
        uint256 from,
        uint256 to
    )
        internal
        pure
        returns (IRangeValidationModule.RangeValidationInput memory)
    {
        return IRangeValidationModule.RangeValidationInput({ from: from, to: to, updateType: BORROW_UPDATE_TYPE });
    }

    function _validate(uint256 agentId, address asset, uint256 from, uint256 to) internal view returns (bool) {
        return rvm.validate(agentHub, agentId, asset, _input(from, to));
    }

    /// @dev Raise from the live borrow cap, as AaveBorrowCapAgent does.
    function _raise(address asset, uint256 to) internal view returns (bool) {
        return _validate(RAISE_AGENT_ID, asset, _liveBorrowCap(asset), to);
    }

    /// @dev Cut from the live borrow cap.
    function _cut(address asset, uint256 to) internal view returns (bool) {
        return _validate(CUT_AGENT_ID, asset, _liveBorrowCap(asset), to);
    }

    function _previewRaise(address asset) internal view returns (bool allowed, uint256 currentCap, uint256 newCap) {
        return rvm.previewRaise(asset, IRvm.CapKind.BORROW);
    }

    function _previewCut(address asset) internal view returns (bool due, uint256 currentCap, uint256 newCap) {
        return rvm.previewCut(asset, IRvm.CapKind.BORROW);
    }

    function _state(address asset) internal view returns (IRvm.ReserveState memory) {
        return rvm.getReserveState(asset, IRvm.CapKind.BORROW);
    }

    function _keyState(address asset) internal view returns (IRvm.KeyState memory) {
        return rvm.getKeyState(asset, IRvm.CapKind.BORROW);
    }
}
