// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {AdminHelperUpgradeable} from "../helpers/AdminHelperUpgradeable.sol";
import {IComet} from "../interfaces/compound/IComet.sol";
import {ICometRewards} from "../interfaces/compound/ICometRewards.sol";
import {UniswapV3Utils} from "../libraries/UniswapV3Utils.sol";
import {IUniswapV3Router} from "../interfaces/uniswap/IUniswapV3Router.sol";

contract SimplifiedStrategyToCompound is AdminHelperUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 public constant SECS_PER_YEAR = 31_556_952;

    /// @notice Uniswap V3 Router
    address public immutable UNISWAPV3_ROUTER;
    /// @notice Uniswap Factory
    address public immutable UNISWAP_FACTORY;
    /// @notice Compound incentive reward
    ICometRewards public immutable COMET_REWARD;
    /// @notice COMP token
    IERC20Upgradeable public immutable COMP;

    struct CometConfig {
        IComet cToken;
        bytes compToWantPath;
    }
    mapping(address => CometConfig) public cometConfig;

    error ErrorInvalidAddress();
    error ErrorInvalidCompRoute();
    error ErrorInvalidCompRouteLength();
    error ErrorNotMatchArray();
    error ErrorInvalidWantRouteLength();

    event EventClaimExtraReward(uint256 compReward, uint256 wantReward);
    event EventRefreshRewardsOwed(uint256 compReward);

    constructor(address comp_, address cometReward_, address uniswapV3Router_) {
        if (
            uniswapV3Router_ == address(0) ||
            comp_ == address(0) ||
            cometReward_ == address(0)
        ) {
            revert ErrorInvalidAddress();
        }

        UNISWAPV3_ROUTER = uniswapV3Router_;
        COMET_REWARD = ICometRewards(cometReward_);
        COMP = IERC20Upgradeable(comp_);
        UNISWAP_FACTORY = IUniswapV3Router(uniswapV3Router_).factory();
    }

    function initialize() external initializer {
        __AdminHelper_init();

        _setTokenToUniswap(address(COMP));
    }

    function addComet(
        address want_,
        address cToken_,
        address[] memory compToWantRoute_,
        uint24[] memory fees_
    ) external onlyAdmin {
        if (want_ == address(0) || cToken_ == address(0)) {
            revert ErrorInvalidAddress();
        }
        uint256 len_ = compToWantRoute_.length;
        if (len_ <= 1) {
            revert ErrorInvalidCompRouteLength();
        }
        if (fees_.length + 1 != len_) {
            revert ErrorNotMatchArray();
        }
        if (
            compToWantRoute_[0] != address(COMP) ||
            compToWantRoute_[len_ - 1] != address(want_)
        ) {
            revert ErrorInvalidCompRoute();
        }
        cometConfig[want_] = CometConfig({
            cToken: IComet(cToken_),
            compToWantPath: UniswapV3Utils.routeToPath(compToWantRoute_, fees_)
        });
        _setAllowanceToThird(want_, cToken_);
    }

    function wantBalance(address want_) public view returns (uint256) {
        return IERC20Upgradeable(want_).balanceOf(address(this));
    }

    function cTokenBalance(address want_) public view returns (uint256) {
        return cometConfig[want_].cToken.balanceOf(address(this));
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

    /*
     * @notice Get the current supply APR in Compound III
     */
    function getSupplyApr(address want_) external view returns (uint256) {
        uint256 utilization_ = cometConfig[want_].cToken.getUtilization();
        return
            cometConfig[want_].cToken.getSupplyRate(utilization_) *
            SECS_PER_YEAR *
            100;
    }

    function compToWant(
        address want_
    ) external view returns (address[] memory) {
        return UniswapV3Utils.pathToRoute(cometConfig[want_].compToWantPath);
    }

    /**
     * @notice Invests the token.
     */
    function deposit(address want_, uint256 amount_) external onlyAdmin {
        IERC20Upgradeable(want_).safeTransferFrom(
            msg.sender,
            address(this),
            amount_
        );
        cometConfig[want_].cToken.supply(want_, amount_);
    }

    /**
     * @dev See {divest}.
     */
    function withdraw(address want_, uint256 amount_) external onlyAdmin {
        uint256 beforeAmount_ = IERC20Upgradeable(want_).balanceOf(
            address(this)
        );
        cometConfig[want_].cToken.withdraw(want_, amount_);
        IERC20Upgradeable(want_).safeTransfer(
            msg.sender,
            IERC20Upgradeable(want_).balanceOf(address(this)) - beforeAmount_
        );
    }

    /*
     * @notice Claims the reward tokens due to governance
     */
    function claimExtraRewards(address want_) external onlyAdmin {
        _claimExtraRewards(want_);
    }

    /*
     * @notice Refresh the amount of reward tokens due to this contract address
     */
    function refreshRewardsOwed(address want_) external {
        emit EventRefreshRewardsOwed(
            COMET_REWARD
                .getRewardOwed(
                    address(cometConfig[want_].cToken),
                    address(this)
                )
                .owed
        );
    }

    /*
     * @notice Claims the reward tokens due to governance
     */
    function _claimExtraRewards(address want_) internal {
        COMET_REWARD.claim(
            address(cometConfig[want_].cToken),
            address(this),
            true
        );
        uint256 balance_ = COMP.balanceOf(address(this));
        uint256 wantReward_ = _swapTokensByUniswap(
            balance_,
            cometConfig[want_].compToWantPath
        );
        IERC20Upgradeable(want_).safeTransfer(msg.sender, wantReward_);
        emit EventClaimExtraReward(balance_, wantReward_);
    }

    function _setAllowanceToThird(address want_, address cToken_) internal {
        uint256 allowance_ = IERC20Upgradeable(want_).allowance(
            address(this),
            cToken_
        );
        IERC20Upgradeable(want_).safeIncreaseAllowance(
            cToken_,
            type(uint256).max - allowance_
        );
    }

    function _setTokenToUniswap(address token_) internal {
        uint256 allowance_ = IERC20Upgradeable(token_).allowance(
            address(this),
            UNISWAPV3_ROUTER
        );
        IERC20Upgradeable(token_).safeIncreaseAllowance(
            UNISWAPV3_ROUTER,
            type(uint256).max - allowance_
        );
    }

    function _swapTokensByUniswap(
        uint256 balance_,
        bytes memory path_
    ) internal returns (uint256) {
        if (balance_ == 0) {
            return 0;
        }
        return UniswapV3Utils.swap(UNISWAPV3_ROUTER, path_, balance_);
    }
}
