// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IReceiver } from "@chainlink/contracts/src/v0.8/keystone/interfaces/IReceiver.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title AbstractReadWriteAccessController - Abstract read/write access controller
abstract contract AbstractReadWriteAccessController is AccessControl {
    bytes32 public constant WRITER_ROLE = keccak256("WRITER_ROLE");
    bytes32 public constant READER_ROLE = keccak256("READER_ROLE");

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }
}
