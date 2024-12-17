// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract AdminHelperUpgradeable is AccessControlUpgradeable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @dev Throws an error if not called by the super admin.
    modifier onlySuperAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Super admin only");
        _;
    }

    /// @dev Throws an error if not called by an admin.
    modifier onlyAdmin() {
        require(
            hasRole(ADMIN_ROLE, _msgSender()) ||
                hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
            "Admin only"
        );
        _;
    }

    /// @dev Initializes the AdminHelperUpgradeable contract.
    function __AdminHelper_init() internal onlyInitializing {
        __AdminHelper_init_unchained();
    }

    function __AdminHelper_init_unchained() internal onlyInitializing {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /// @notice Check if admin.
    /// @param address_ Address used for the check.
    /// @return If an admin returns true, otherwise return false.
    function isAdmin(address address_) public view returns (bool) {
        return
            hasRole(ADMIN_ROLE, address_) ||
            hasRole(DEFAULT_ADMIN_ROLE, address_);
    }
}
