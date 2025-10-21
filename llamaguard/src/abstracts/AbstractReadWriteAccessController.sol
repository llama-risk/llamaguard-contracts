// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IReceiver } from "@chainlink/contracts/src/v0.8/keystone/interfaces/IReceiver.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title IReceiverTemplate - Abstract receiver with workflow validation and metadata decoding
abstract contract AbstractReadWriteAccessController is AccessControl {
    bytes32 private constant WRITER_ROLE = keccak256("WRITER_ROLE");
    bytes32 private constant READER_ROLE = keccak256("READER_ROLE");

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(WRITER_ROLE, msg.sender);
        _grantRole(READER_ROLE, msg.sender);
    }

    function hasWriteAccess(address account) public view returns (bool) {
        return hasRole(WRITER_ROLE, account);
    }

    function hasReadAccess(address account) public view returns (bool) {
        return hasRole(READER_ROLE, account);
    }

    function hasAccess(address account) public view returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, account) || hasRole(WRITER_ROLE, account) || hasRole(READER_ROLE, account);
    }
}
