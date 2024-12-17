// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {AdminHelperUpgradeable} from "../helpers/AdminHelperUpgradeable.sol";
import {UniswapV2Utils} from "../libraries/UniswapV2Utils.sol";
import {IStakingRewards} from "../interfaces/sky/IStakingRewards.sol";
import {SimplifiedManager} from "./SimplifiedManager.sol";

contract SimplifiedStrategyToSkyFarm is AdminHelperUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice Uniswap Router
    address public immutable UNISWAPV2_ROUTER;
    address public immutable USDS;
    IStakingRewards public immutable STAKING_REWARD;
    address public immutable REWARD_TOKEN;

    SimplifiedManager public assetManager;

    event EventDeposit(uint256 amount);
    event EventWithdraw(uint256 amount);
    event EventClaimReward(uint256 amount);

    error ErrorInvalidAddress();
    error ErrorNotMatchArray();
    error ErrorInvalidWantRouteLength();

    constructor(
        address usds_,
        address rewardToken_,
        address stakingReward_,
        address uniswapV2Router_
    ) {
        if (
            usds_ == address(0) ||
            rewardToken_ == address(0) ||
            stakingReward_ == address(0) ||
            uniswapV2Router_ == address(0)
        ) {
            revert ErrorInvalidAddress();
        }

        USDS = usds_;
        STAKING_REWARD = IStakingRewards(stakingReward_);
        REWARD_TOKEN = rewardToken_;
        UNISWAPV2_ROUTER = uniswapV2Router_;
    }

    function initialize(address assetManager_) external initializer {
        __AdminHelper_init();
        if (assetManager_ == address(0)) {
            revert ErrorInvalidAddress();
        }

        assetManager = SimplifiedManager(assetManager_);
        assetManager.applyAllowance(USDS);

        _setAllowanceToThird(USDS, address(STAKING_REWARD));
        _setAllowanceToThird(REWARD_TOKEN, UNISWAPV2_ROUTER);
    }

    function wantBalance() public view returns (uint256) {
        return IERC20Upgradeable(USDS).balanceOf(address(this));
    }

    function assetBalance() public view returns (uint256) {
        return STAKING_REWARD.balanceOf(address(this));
    }

    function rewardBalance() public view returns (uint256) {
        return STAKING_REWARD.earned(address(this));
    }

    function ethToWant(
        address[] memory path_,
        uint256 amount_
    ) public view returns (uint256) {
        return
            UniswapV2Utils.getAmountsOutByPath(
                UNISWAPV2_ROUTER,
                amount_,
                path_
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
        require(amount_ > 0);
        IERC20Upgradeable(USDS).safeTransferFrom(
            address(assetManager),
            address(this),
            amount_
        );
        STAKING_REWARD.stake(amount_);
        emit EventDeposit(amount_);
    }

    function withdraw(uint256 amount_) external {
        require(amount_ > 0);
        STAKING_REWARD.withdraw(amount_);
        IERC20Upgradeable(USDS).safeTransfer(address(assetManager), amount_);
        emit EventWithdraw(amount_);
    }

    function claim() external {
        STAKING_REWARD.getReward();
        uint256 bal_ = IERC20Upgradeable(REWARD_TOKEN).balanceOf(address(this));
        address[] memory path_ = new address[](2);
        path_[0] = REWARD_TOKEN;
        path_[1] = USDS;

        UniswapV2Utils.swap(
            UNISWAPV2_ROUTER,
            bal_,
            path_,
            address(assetManager)
        );
        emit EventClaimReward(bal_);
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
