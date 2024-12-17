// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {AdminHelperUpgradeable} from "../helpers/AdminHelperUpgradeable.sol";

contract SimplifiedManager is AdminHelperUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    error ErrorInvalidAddress();
    error ErrorNotMatchArray();
    error ErrorInvalidWantRouteLength();

    function initialize() external initializer {
        __AdminHelper_init();
    }

    function transferToAccount(
        address account_,
        address token_,
        uint256 amount_
    ) external onlyAdmin {
        require(account_ != address(0), "RECOVER_VAULT_ZERO");

        if (token_ == address(0)) {
            // Transfer replaced by call to prevent transfer gas amount issue
            (bool os, ) = account_.call{value: amount_}("");
            require(os, "RECOVER_TRANSFER_FAILED");
        } else {
            // safeTransfer comes from the overridden default implementation
            IERC20Upgradeable(token_).safeTransfer(account_, amount_);
        }
    }

    function applyAllowance(address want_) external {
        require(isAdmin(tx.origin), "Admin only");
        uint256 allowance_ = IERC20Upgradeable(want_).allowance(
            address(this),
            address(msg.sender)
        );
        if (allowance_ < type(uint256).max / 2) {
            IERC20Upgradeable(want_).safeIncreaseAllowance(
                address(msg.sender),
                type(uint256).max - allowance_
            );
        }
    }
}
