// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IReceiver } from "@chainlink/contracts/src/v0.8/keystone/interfaces/IReceiver.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title AbstractReadWriteAccessController
 * @notice Abstract base contract providing role-based read/write access control
 * @dev Extends OpenZeppelin AccessControl with predefined WRITER_ROLE and READER_ROLE.
 *      Derived contracts should use these roles to gate write and read operations.
 */
abstract contract AbstractReadWriteAccessController is AccessControl {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Role identifier for accounts authorized to write/update data
    bytes32 public constant WRITER_ROLE = keccak256("WRITER_ROLE");

    /// @notice Role identifier for accounts authorized to read data (optional restriction)
    bytes32 public constant READER_ROLE = keccak256("READER_ROLE");

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initializes the access controller with an admin account
     * @param admin Address to receive DEFAULT_ADMIN_ROLE, allowing role management
     */
    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }
}
