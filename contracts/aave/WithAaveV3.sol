// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
//import {IComet} from "../interfaces/compound/IComet.sol";
//import {ICometRewards} from "../interfaces/compound/ICometRewards.sol";
import {UniswapV3Utils} from "../libraries/UniswapV3Utils.sol";
import {IAToken, IRewardsController} from "../interfaces/aave/IAtoken.sol";
import {IPool} from "../interfaces/aave/IPool.sol";

contract WithAaveV3 is Initializable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 public constant SECS_PER_YEAR = 31_556_952;

    /// @notice Uniswap V3 Router
    address public immutable UNISWAPV3_ROUTER;
    /// @notice The pool to deposit and withdraw through.
    IPool public immutable AAVEPOOL;
    /// @notice The token that we get in return for deposits.
    IAToken public immutable ATOKEN;
    /// @notice The a Token specific rewards contract for claiming rewards.
    IRewardsController public immutable REWARDS_CONTROLLER;

    IERC20Upgradeable public want;

    /// @notice reward token => token to want bytes
    mapping(address => bytes) public tokenToWantPathMapping;

    error ErrorInvalidAddress();
    error ErrorWantAndATokenNotMatch(address want, address atoken);

    constructor(address aavePool_, address aToken_, address uniswapV3Router_) {
        if (
            aavePool_ == address(0) ||
            aToken_ == address(0) ||
            uniswapV3Router_ == address(0)
        ) {
            revert ErrorInvalidAddress();
        }

        AAVEPOOL = IPool(aavePool_);

        UNISWAPV3_ROUTER = uniswapV3Router_;

        // Set the aToken based on the asset we are using.
        ATOKEN = IAToken(aToken_);

        // Set the rewards controller
        REWARDS_CONTROLLER = ATOKEN.getIncentivesController();
    }

    function initialize(address want_) external initializer {
        if (want_ == address(0)) {
            revert ErrorInvalidAddress();
        }
        if (ATOKEN.UNDERLYING_ASSET_ADDRESS() != want_) {
            revert ErrorWantAndATokenNotMatch(want_, address(ATOKEN));
        }

        want = IERC20Upgradeable(want_);
        _setAllowanceToThird();
    }

    struct RewardTokenSwapParam {
        address rewardToken;
        address[] rwdTokenToWantRoute;
        uint24[] fees;
    }

    function setRewardTokenSwapParam(
        RewardTokenSwapParam[] calldata params_
    ) external {
        uint256 len_ = params_.length;
        for (uint256 i = 0; i < len_; i++) {
            RewardTokenSwapParam memory data_ = params_[i];
            tokenToWantPathMapping[data_.rewardToken] = UniswapV3Utils
                .routeToPath(data_.rwdTokenToWantRoute, data_.fees);
        }
    }

    function aTokenBalance() public view virtual returns (uint256) {
        return ATOKEN.balanceOf(address(this));
    }

    function invest(uint256 amount_) external {
        AAVEPOOL.supply(address(want), amount_, address(this), 0);
    }

    function divest(uint256 amount_) external {
        AAVEPOOL.withdraw(address(want), amount_, address(this));
    }

    /*
     * @notice Claims the reward tokens due to governance
     */
    function claimExtraRewards() external {
        _claimAndSellRewards();
    }

    /**
     * @notice Used to claim any pending rewards and sell them to asset.
     */
    function _claimAndSellRewards() internal {
        if (REWARDS_CONTROLLER.getRewardsByAsset(address(ATOKEN)).length == 0) {
            return;
        }
        //claim all rewards
        address[] memory assets_ = new address[](1);
        assets_[0] = address(ATOKEN);
        (address[] memory rewardsList_, ) = REWARDS_CONTROLLER
            .claimAllRewardsToSelf(assets_);

        //swap as much as possible back to want
        address token_;
        for (uint256 i = 0; i < rewardsList_.length; ++i) {
            token_ = rewardsList_[i];

            if (token_ == address(want)) {
                continue;
            } else {
                bytes memory path_ = tokenToWantPathMapping[token_];
                if (path_.length == 0) {
                    continue;
                }
                uint256 balance_ = IERC20Upgradeable(token_).balanceOf(
                    address(this)
                );

                if (balance_ > 0) {
                    UniswapV3Utils.swap(UNISWAPV3_ROUTER, path_, balance_);
                }
            }
        }
    }

    function _setAllowanceToThird() internal {
        uint256 allowance_ = IERC20Upgradeable(address(want)).allowance(
            address(this),
            address(AAVEPOOL)
        );
        IERC20Upgradeable(address(want)).safeIncreaseAllowance(
            address(AAVEPOOL),
            type(uint256).max - allowance_
        );
    }
}
