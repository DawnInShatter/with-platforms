// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {AdminHelperUpgradeable} from "../helpers/AdminHelperUpgradeable.sol";
import {IAToken, IRewardsController} from "../interfaces/seamless/IAToken.sol";
import {IPool} from "../interfaces/seamless/IPool.sol";
import {UniswapV3Utils} from "../libraries/UniswapV3Utils.sol";
import {IUniswapV3Router} from "../interfaces/uniswap/IUniswapV3Router.sol";

contract SimplifiedStrategyToSeamless is AdminHelperUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice Uniswap V3 Router
    address public immutable UNISWAPV3_ROUTER;
    /// @notice Uniswap Factory
    address public immutable UNISWAP_FACTORY;
    /// @notice The pool to deposit and withdraw through.
    IPool public immutable SEAMLESS_POOL;
    /// @notice The a Token specific rewards contract for claiming rewards.
    IRewardsController public immutable REWARDS_CONTROLLER;

    mapping(address => InvestConfig) public investConfig;

    struct InvestConfig {
        IAToken aToken;
        mapping(address => bytes) tokenToWantPathMapping;
    }

    struct RewardTokenSwapParam {
        address rewardToken;
        address[] rwdTokenToWantRoute;
        uint24[] fees;
    }

    error ErrorInvalidAddress();
    error ErrorInvalidRewardToWantRoute();
    error ErrorNotMatchArray();
    error ErrorInvalidWantRouteLength();

    event EventClaimExtraReward(
        address want,
        address[] rewardTokens,
        uint256[2][] rewardList
    );

    constructor(
        address pool_,
        address rewardsController_,
        address uniswapV3Router_
    ) {
        if (
            pool_ == address(0) ||
            rewardsController_ == address(0) ||
            uniswapV3Router_ == address(0)
        ) {
            revert ErrorInvalidAddress();
        }

        SEAMLESS_POOL = IPool(pool_);
        REWARDS_CONTROLLER = IRewardsController(rewardsController_);
        UNISWAPV3_ROUTER = uniswapV3Router_;
        UNISWAP_FACTORY = IUniswapV3Router(uniswapV3Router_).factory();
    }

    function initialize() external initializer {
        __AdminHelper_init();
    }

    function addInvestConfig(
        address want_,
        address aToken_,
        RewardTokenSwapParam[] calldata params_
    ) external onlyAdmin {
        if (want_ == address(0) || aToken_ == address(0)) {
            revert ErrorInvalidAddress();
        }
        if (IAToken(aToken_).getIncentivesController() != REWARDS_CONTROLLER) {
            revert ErrorInvalidAddress();
        }
        investConfig[want_].aToken = IAToken(aToken_);
        uint256 len_ = params_.length;
        for (uint256 i = 0; i < len_; i++) {
            RewardTokenSwapParam memory data_ = params_[i];
            if (
                data_.rwdTokenToWantRoute[
                    data_.rwdTokenToWantRoute.length - 1
                ] != address(want_)
            ) {
                revert ErrorInvalidRewardToWantRoute();
            }
            investConfig[want_].tokenToWantPathMapping[
                data_.rewardToken
            ] = UniswapV3Utils.routeToPath(
                data_.rwdTokenToWantRoute,
                data_.fees
            );
        }
        _setAllowanceToThird(want_, address(SEAMLESS_POOL));
        _refreshTokenSwapAllowance(want_);
    }

    function wantBalance(address want_) public view returns (uint256) {
        return IERC20Upgradeable(want_).balanceOf(address(this));
    }

    function aTokenBalance(address want_) public view returns (uint256) {
        return investConfig[want_].aToken.balanceOf(address(this));
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

    function getRewardAssets(
        address want_
    ) public view returns (address[] memory) {
        return
            REWARDS_CONTROLLER.getRewardsByAsset(
                address(investConfig[want_].aToken)
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

    /**
     * @notice Invests the token.
     */
    function deposit(address want_, uint256 amount_) external {
        uint256 balance_ = IERC20Upgradeable(want_).balanceOf(address(this));
        if (balance_ > 0) {
            SEAMLESS_POOL.supply(want_, amount_, address(this), 0);
        }
    }

    /**
     * @dev See {divest}.
     */
    function withdraw(address want_, uint256 amount_) external {
        SEAMLESS_POOL.withdraw(want_, amount_, address(this));
    }

    /*
     * @notice Claims the reward tokens due to governance
     */
    function claimExtraRewards(address want_) external {
        _claimAndSellRewards(want_);
    }

    function refreshTokenSwapAllowance(address want_) external onlyAdmin {
        _refreshTokenSwapAllowance(want_);
    }

    /**
     * @notice Used to claim any pending rewards and sell them to asset.
     * @dev Use `claimRewardsToSelf`, not `claimAllRewardsToSelf`.
     *  Because when `claimAllRewardsToSelf` is used, some reward tokens are 0 and revert.
     */
    function _claimAndSellRewards(address want_) internal {
        //claim all rewards
        address aToken_ = address(investConfig[want_].aToken);
        address[] memory assets_ = new address[](1);
        assets_[0] = aToken_;

        address[] memory rewardsList_ = REWARDS_CONTROLLER.getRewardsByAsset(
            aToken_
        );

        //swap as much as possible back to want
        address token_;
        uint256 len_ = rewardsList_.length;
        uint256[2][] memory rwdList_ = new uint256[2][](len_);
        for (uint256 i = 0; i < len_; ++i) {
            token_ = rewardsList_[i];
            uint256 amount_ = REWARDS_CONTROLLER.claimRewardsToSelf(
                assets_,
                type(uint256).max,
                token_
            );
            rwdList_[i][0] = amount_;

            if (token_ == address(want_)) {
                continue;
            } else {
                bytes memory path_ = investConfig[want_].tokenToWantPathMapping[
                    token_
                ];
                if (path_.length == 0) {
                    continue;
                }
                uint256 balance_ = IERC20Upgradeable(token_).balanceOf(
                    address(this)
                );

                if (balance_ > 0) {
                    rwdList_[i][1] = UniswapV3Utils.swap(
                        UNISWAPV3_ROUTER,
                        path_,
                        balance_
                    );
                }
            }
        }
        emit EventClaimExtraReward(want_, rewardsList_, rwdList_);
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

    function _refreshTokenSwapAllowance(address want_) internal {
        address[] memory assets_ = REWARDS_CONTROLLER.getRewardsByAsset(
            address(investConfig[want_].aToken)
        );
        for (uint256 i = 0; i < assets_.length; i++) {
            _setAllowanceToThird(assets_[i], UNISWAPV3_ROUTER);
        }
    }
}
