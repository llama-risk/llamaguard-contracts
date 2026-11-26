// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IPool } from "aave-v3-origin/src/contracts/interfaces/IPool.sol";
import { DataTypes } from "aave-v3-origin/src/contracts/protocol/libraries/types/DataTypes.sol";
import {
    ReserveConfiguration
} from "aave-v3-origin/src/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {
    IAaveV3ConfigEngine as IEngine
} from "aave-v3-origin/src/contracts/extensions/v3-config-engine/IAaveV3ConfigEngine.sol";
import { EngineFlags } from "aave-v3-origin/src/contracts/extensions/v3-config-engine/EngineFlags.sol";

/// @title ShadowPool
/// @notice Staging only, never deployed to production and outside the audit scope. A read-only view of a real Aave
///         V3 Pool in which only the borrow cap is ours. The caps stack (RVM, agents, registry, workflow) is pointed
///         at this address, so it runs unchanged on live debt while its writes land here instead of on Aave.
/// @dev Three roles in one contract:
///      - Pool reads. `getConfiguration` returns the real configuration with our borrow cap swapped in, once one of
///        our agents has written one for that asset; until then it is Aave's live cap. Every other call is forwarded
///        to the real Pool by `staticcall`, so nothing sent here can change Aave state or move funds.
///      - Write target. The agents' `agentContext` points here: `AaveBorrowCapAgent` delegatecalls `updateCaps`,
///        which runs in the agent's storage, so it writes nothing and only calls `setBorrowCap` on this contract
///        through the immutable `SELF`. The caller of `setBorrowCap` is then the agent.
///      - Allowlist. Only the writers the owner sets (the raise and cut agents) can move a cap.
contract ShadowPool is Ownable {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    /// @notice Zero address passed as the real Pool or the owner.
    error ZeroAddress();

    /// @notice `setBorrowCap` called by an address that is not an allowed writer.
    error NotWriter(address caller);

    /// @notice `updateCaps` called directly instead of by delegatecall from an agent.
    error OnlyDelegateCall();

    /// @notice `setBorrowCap` above Aave's maximum borrow cap.
    error BorrowCapTooHigh(uint256 cap);

    /// @notice Emitted when an agent moves a borrow cap.
    /// @param asset the reserve
    /// @param oldCap the cap before the write: our last one, or Aave's cap on the first write
    /// @param newCap the cap written, in whole tokens
    /// @param writer the agent that wrote it
    event ShadowBorrowCapSet(address indexed asset, uint256 oldCap, uint256 newCap, address indexed writer);

    /// @notice Emitted when the owner allows or removes a writer.
    event WriterSet(address indexed writer, bool allowed);

    /// @notice The real Aave V3 Pool every read comes from.
    IPool public immutable REAL_POOL;

    /// @dev This contract's own address, read from bytecode so it stays correct under delegatecall.
    address private immutable SELF;

    /// @notice Whether an address may call `setBorrowCap`.
    mapping(address writer => bool allowed) public isWriter;

    /// @dev Our borrow cap plus one; zero means none written yet, so the real cap applies.
    mapping(address asset => uint256 capPlusOne) private _shadowCap;

    /// @param realPool the Aave V3 Pool to read from
    /// @param owner_ manages the writer allowlist
    constructor(IPool realPool, address owner_) Ownable(owner_) {
        if (address(realPool) == address(0)) revert ZeroAddress();
        REAL_POOL = realPool;
        SELF = address(this);
    }

    /// @notice The real reserve configuration, with our borrow cap once one has been written.
    function getConfiguration(address asset) external view returns (DataTypes.ReserveConfigurationMap memory config) {
        config = REAL_POOL.getConfiguration(asset);
        uint256 stored = _shadowCap[asset];
        if (stored != 0) config.setBorrowCap(stored - 1);
    }

    /// @notice The borrow cap the caps stack sees: ours once written, Aave's before.
    function borrowCap(address asset) public view returns (uint256) {
        uint256 stored = _shadowCap[asset];
        return stored == 0 ? realBorrowCap(asset) : stored - 1;
    }

    /// @notice Aave's own borrow cap, to record next to ours.
    function realBorrowCap(address asset) public view returns (uint256) {
        return REAL_POOL.getConfiguration(asset).getBorrowCap();
    }

    /// @notice Whether one of our agents has written a cap for `asset`.
    function hasShadowCap(address asset) external view returns (bool) {
        return _shadowCap[asset] != 0;
    }

    /// @notice Allows or removes a writer.
    function setWriter(address writer, bool allowed) external onlyOwner {
        if (writer == address(0)) revert ZeroAddress();
        isWriter[writer] = allowed;
        emit WriterSet(writer, allowed);
    }

    /// @notice Moves our borrow cap for `asset`. Reverts above Aave's maximum borrow cap, as the config engine would.
    function setBorrowCap(address asset, uint256 cap) external {
        if (!isWriter[msg.sender]) revert NotWriter(msg.sender);
        // Aave's own bound, so getConfiguration can always swap the cap in.
        if (cap > ReserveConfiguration.MAX_VALID_BORROW_CAP) revert BorrowCapTooHigh(cap);
        uint256 oldCap = borrowCap(asset);
        _shadowCap[asset] = cap + 1;
        emit ShadowBorrowCapSet(asset, oldCap, cap, msg.sender);
    }

    /// @notice The config engine entry the agents delegatecall. Applies each borrow cap that is not KEEP_CURRENT;
    ///         supply caps are ignored.
    /// @dev Runs in the agent's storage, so it must not write storage. `SELF` is an immutable, read from code.
    function updateCaps(IEngine.CapsUpdate[] calldata updates) external {
        if (address(this) == SELF) revert OnlyDelegateCall();
        for (uint256 i; i < updates.length; ++i) {
            if (updates[i].borrowCap != EngineFlags.KEEP_CURRENT) {
                ShadowPool(SELF).setBorrowCap(updates[i].asset, updates[i].borrowCap);
            }
        }
    }

    /// @dev Every other Pool call goes to the real Pool by staticcall, with its return data or revert passed back.
    ///      A call that would change state reverts there.
    fallback() external {
        (bool ok, bytes memory data) = address(REAL_POOL).staticcall(msg.data);
        assembly ("memory-safe") {
            switch ok
            case 0 { revert(add(data, 32), mload(data)) }
            default { return(add(data, 32), mload(data)) }
        }
    }
}
