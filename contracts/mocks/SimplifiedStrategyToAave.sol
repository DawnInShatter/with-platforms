// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {AdminHelperUpgradeable} from "../helpers/AdminHelperUpgradeable.sol";
import {IProtocolDataProvider} from "../interfaces/aave/IProtocolDataProvider.sol";
import {IAToken, IRewardsController} from "../interfaces/aave/IAtoken.sol";
import {IPool, DataTypesV3} from "../interfaces/aave/IPool.sol";
import {IReserveInterestRateStrategy} from "../interfaces/aave/IReserveInterestRateStrategy.sol";
import {UniswapV3Utils} from "../libraries/UniswapV3Utils.sol";
import {IUniswapV3Router} from "../interfaces/uniswap/IUniswapV3Router.sol";
import {ReserveConfiguration} from "../libraries/aavev3/ReserveConfiguration.sol";

contract SimplifiedStrategyToAave is AdminHelperUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using ReserveConfiguration for DataTypesV3.ReserveConfigurationMap;

    /// @notice Uniswap V3 Router
    address public immutable UNISWAPV3_ROUTER;
    /// @notice Uniswap Factory
    address public immutable UNISWAP_FACTORY;
    IProtocolDataProvider public immutable PROTOCOL_DATA_PROVIDER;
    /// @notice The pool to deposit and withdraw through.
    IPool public immutable AAVEPOOL;
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
        address protocolDataProvider_,
        address rewardsController_,
        address uniswapV3Router_
    ) {
        if (
            protocolDataProvider_ == address(0) ||
            rewardsController_ == address(0) ||
            uniswapV3Router_ == address(0)
        ) {
            revert ErrorInvalidAddress();
        }

        PROTOCOL_DATA_PROVIDER = IProtocolDataProvider(protocolDataProvider_);
        AAVEPOOL = IPool(PROTOCOL_DATA_PROVIDER.ADDRESSES_PROVIDER().getPool());
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
        _setAllowanceToThird(want_, address(AAVEPOOL));
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

    /**
     * @notice Calculate the new apr after deposit `extraAmount_` 'want' token.
     * @param extraAmount_ How much 'want' to deposit.
     */
    function aprAfterDeposit(
        address want_,
        uint256 extraAmount_
    ) external view returns (uint256) {
        // Need to calculate new supplyRate after Deposit (when deposit has not been done yet).
        DataTypesV3.ReserveData memory reserveData_ = AAVEPOOL
            .getReserveDataExtended(want_);

        (
            uint256 unbacked_,
            ,
            ,
            uint256 totalStableDebt_,
            uint256 totalVariableDebt_,
            ,
            ,
            ,
            uint256 averageStableBorrowRate_,
            ,
            ,

        ) = PROTOCOL_DATA_PROVIDER.getReserveData(want_);

        (, , , , uint256 reserveFactor_, , , , , ) = PROTOCOL_DATA_PROVIDER
            .getReserveConfigurationData(want_);

        DataTypesV3.CalculateInterestRatesParams memory params_ = DataTypesV3
            .CalculateInterestRatesParams(
                unbacked_,
                extraAmount_,
                0,
                totalStableDebt_,
                totalVariableDebt_,
                averageStableBorrowRate_,
                reserveFactor_,
                want_,
                reserveData_.configuration.getIsVirtualAccActive(),
                reserveData_.virtualUnderlyingBalance
            );

        (uint256 newLiquidityRate_, , ) = IReserveInterestRateStrategy(
            reserveData_.interestRateStrategyAddress
        ).calculateInterestRates(params_);

        return newLiquidityRate_ / 1e9; // Divided by 1e9 to go from Ray to Wad
    }

    function apr(address want_) external view returns (uint256) {
        // Dividing by 1e9 to pass from ray to wad.
        return
            uint256(
                AAVEPOOL.getReserveDataExtended(want_).currentLiquidityRate
            ) / 1e9;
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
            AAVEPOOL.supply(want_, amount_, address(this), 0);
        }
    }

    /**
     * @dev See {divest}.
     */
    function withdraw(address want_, uint256 amount_) external {
        AAVEPOOL.withdraw(want_, amount_, address(this));
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
     */
    function _claimAndSellRewards(address want_) internal {
        //claim all rewards
        address[] memory assets_ = new address[](1);
        assets_[0] = address(investConfig[want_].aToken);
        (
            address[] memory rewardsList_,
            uint256[] memory claimedAmounts
        ) = REWARDS_CONTROLLER.claimAllRewardsToSelf(assets_);

        //swap as much as possible back to want
        address token_;
        uint256 len_ = rewardsList_.length;
        uint256[2][] memory rwdList_ = new uint256[2][](len_);
        for (uint256 i = 0; i < len_; ++i) {
            token_ = rewardsList_[i];
            rwdList_[i][0] = claimedAmounts[i];

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
