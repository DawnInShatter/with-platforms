// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IVault} from "../interfaces/beefy/IVault.sol";

contract WithBeefy is Initializable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 public constant SECS_PER_YEAR = 31_556_952;

    IVault public BEEFY_VAULT;

    IERC20Upgradeable public want;

    error ErrorInvalidAddress();

    function initialize(
        address want_,
        address beefyVault_
    ) external initializer {
        if (want_ == address(0) || beefyVault_ == address(0)) {
            revert ErrorInvalidAddress();
        }

        want = IERC20Upgradeable(want_);
        BEEFY_VAULT = IVault(beefyVault_);
        _setAllowanceToThird();
    }

    function setBeefyVault(address addr_) external {
        BEEFY_VAULT = IVault(addr_);
    }

    function vaultBalance() public view virtual returns (uint256) {
        uint256 share_ = BEEFY_VAULT.balanceOf(address(this));
        return (share_ * BEEFY_VAULT.balance()) / BEEFY_VAULT.totalSupply();
    }

    function invest(uint256 amount_) external {
        BEEFY_VAULT.deposit(amount_);
    }

    function investAll() external {
        BEEFY_VAULT.depositAll();
    }

    function divest(uint256 amount_) external {
        BEEFY_VAULT.withdraw(amount_);
    }

    function divestAll() external {
        BEEFY_VAULT.withdrawAll();
    }

    function _setAllowanceToThird() internal {
        uint256 allowance_ = IERC20Upgradeable(address(want)).allowance(
            address(this),
            address(BEEFY_VAULT)
        );
        IERC20Upgradeable(address(want)).safeIncreaseAllowance(
            address(BEEFY_VAULT),
            type(uint256).max - allowance_
        );
    }
}
