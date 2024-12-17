// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {AdminHelperUpgradeable} from "../helpers/AdminHelperUpgradeable.sol";
import {UniswapV3Utils} from "../libraries/UniswapV3Utils.sol";
import {IStakedUSDe} from "../interfaces/ethena/IStakedUSDe.sol";
import {SimplifiedManager} from "./SimplifiedManager.sol";

contract SimplifiedStrategyToEthena is AdminHelperUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice Uniswap Factory
    address public immutable UNISWAP_FACTORY;
    address public immutable USDE;
    IStakedUSDe public immutable STAKED_USDE;

    SimplifiedManager public assetManager;

    event EventDepositUSDe(uint256 shares);
    event EventUnstakeWithCooldown(uint256 shareAmount);
    event EventWithdraw(uint256 claimedAmount);

    error ErrorInvalidAddress();
    error ErrorNotMatchArray();
    error ErrorInvalidWantRouteLength();

    constructor(address usde_, address susde_, address uniswapV3Factory_) {
        if (
            usde_ == address(0) ||
            susde_ == address(0) ||
            uniswapV3Factory_ == address(0)
        ) {
            revert ErrorInvalidAddress();
        }

        USDE = usde_;
        STAKED_USDE = IStakedUSDe(susde_);
        UNISWAP_FACTORY = uniswapV3Factory_;
    }

    function initialize(address assetManager_) external initializer {
        __AdminHelper_init();
        if (assetManager_ == address(0)) {
            revert ErrorInvalidAddress();
        }

        assetManager = SimplifiedManager(assetManager_);
        assetManager.applyAllowance(USDE);
    }

    function wantBalance() public view returns (uint256) {
        return IERC20Upgradeable(USDE).balanceOf(address(this));
    }

    function sUSDeAssetBalance() public view returns (uint256) {
        return STAKED_USDE.previewRedeem(sUSDeBalance());
    }

    function sUSDeBalance() public view returns (uint256) {
        return STAKED_USDE.balanceOf(address(this));
    }

    function getCooldowning()
        public
        view
        returns (IStakedUSDe.UserCooldown memory)
    {
        return STAKED_USDE.cooldowns(address(this));
    }

    function getCooldownedAmount() public view returns (uint256) {
        IStakedUSDe.UserCooldown memory data_ = STAKED_USDE.cooldowns(
            address(this)
        );
        if (data_.cooldownEnd <= block.timestamp) {
            return data_.underlyingAmount;
        }
        return 0;
    }

    function ethToToken(
        uint256 amount_,
        address[] memory tokensRouteRoute_,
        uint24[] memory fees_
    ) public view returns (uint256) {
        uint256 len_ = tokensRouteRoute_.length;
        if (len_ <= 1) {
            revert ErrorInvalidWantRouteLength();
        }
        if (fees_.length + 1 != len_) {
            revert ErrorNotMatchArray();
        }
        bytes memory tokensRoutePath_ = UniswapV3Utils.routeToPath(
            tokensRouteRoute_,
            fees_
        );
        return
            UniswapV3Utils.getAmountsOutByPath(
                UNISWAP_FACTORY,
                tokensRoutePath_,
                amount_
            );
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

    function deposit(uint256 amount_) external {
        IERC20Upgradeable(USDE).safeTransferFrom(
            address(assetManager),
            address(this),
            amount_
        );
        uint256 shares_ = STAKED_USDE.deposit(amount_, address(this));
        emit EventDepositUSDe(shares_);
    }

    function unstakeWithCooldown(uint256 shareAmount_) external {
        uint256 claimedAmount_ = getCooldownedAmount();
        if (claimedAmount_ > 0) {
            STAKED_USDE.unstake(address(this));
            IERC20Upgradeable(USDE).safeTransfer(
                address(assetManager),
                claimedAmount_
            );
            emit EventWithdraw(claimedAmount_);
        }
        STAKED_USDE.cooldownShares(shareAmount_);
        emit EventUnstakeWithCooldown(shareAmount_);
    }

    function withdraw() external {
        uint256 claimedAmount_ = getCooldownedAmount();
        if (claimedAmount_ > 0) {
            STAKED_USDE.unstake(address(this));
            IERC20Upgradeable(USDE).safeTransfer(
                address(assetManager),
                claimedAmount_
            );
            emit EventWithdraw(claimedAmount_);
        }
    }

    function _setAllowanceToThird(address want_, address third_) internal {
        uint256 allowance_ = IERC20Upgradeable(want_).allowance(
            address(this),
            third_
        );
        if (allowance_ < type(uint256).max / 2) {
            IERC20Upgradeable(want_).safeIncreaseAllowance(
                third_,
                type(uint256).max - allowance_
            );
        }
    }
}
