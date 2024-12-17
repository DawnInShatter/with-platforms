// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IComet} from "../interfaces/compound/IComet.sol";
import {ICometRewards} from "../interfaces/compound/ICometRewards.sol";

contract WithCompoundV3 is Initializable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 public constant SECS_PER_YEAR = 31_556_952;

    IERC20Upgradeable public want;
    /// @notice Compound pool
    IComet public cToken;
    /// @notice Compound incentive reward
    ICometRewards public cometReward;
    /// @notice comp token
    IERC20Upgradeable public comp;
    /// @notice Owed reward from comet
    uint256 internal _cometRewardOwed;

    error ErrorInvalidAddress();

    function initialize(
        address want_,
        address cToken_,
        address cometReward_
    ) external initializer {
        if (
            want_ == address(0) ||
            cToken_ == address(0) ||
            cometReward_ == address(0)
        ) {
            revert ErrorInvalidAddress();
        }

        want = IERC20Upgradeable(want_);
        cToken = IComet(cToken_);
        cometReward = ICometRewards(cometReward_);
        comp = IERC20Upgradeable(cometReward.rewardConfig(cToken_).token);
        _setAllowanceToLender();
    }

    function setCToken(address addr_) external {
        cToken = IComet(addr_);
    }

    function setCometReward(address addr_) external {
        cometReward = ICometRewards(addr_);
    }

    function setComp() external {
        comp = IERC20Upgradeable(
            cometReward.rewardConfig(address(cToken)).token
        );
    }

    function ctokenBalance() public view virtual returns (uint256) {
        return cToken.balanceOf(address(this));
    }

    function invest(uint256 amount_) external {
        cToken.supply(address(want), amount_);
    }

    function divest(uint256 amount_) external {
        cToken.withdraw(address(want), amount_);
    }

    /*
     * @notice Refresh the amount of reward tokens due to this contract address
     */
    function refreshRewardsOwed() external virtual {
        _cometRewardOwed = cometReward
            .getRewardOwed(address(cToken), address(this))
            .owed;
    }

    /*
     * @notice Claims the reward tokens due to governance
     */
    function claimExtraRewards() external {
        _claimExtraRewards();
        _cometRewardOwed = 0;
    }

    /*
     * @notice Get the amount of reward tokens due to this contract address
     */
    function getRewardsOwed() external view virtual returns (uint256) {
        return _cometRewardOwed;
    }

    /*
     * @notice Get the current supply APR in Compound III
     */
    function getSupplyApr() external view virtual returns (uint256) {
        uint256 utilization_ = cToken.getUtilization();
        return cToken.getSupplyRate(utilization_) * SECS_PER_YEAR * 100;
    }

    /**
     * @notice Calculate the new apr after deposit `extraAmount_` 'want' token.
     * @param extraAmount_ How much 'want' to deposit.
     */
    function aprAfterDeposit(
        uint256 extraAmount_
    ) external view virtual returns (uint256) {
        // Need to calculate new supplyRate after Deposit (when deposit has not been done yet).
        uint256 utilization_ = _getUtilizationAfterDeposit(extraAmount_);
        return cToken.getSupplyRate(utilization_) * SECS_PER_YEAR * 100;
    }

    /*
     * @notice Claims the reward tokens due to governance
     */
    function _claimExtraRewards() internal virtual {
        cometReward.claim(address(cToken), address(this), true);
    }

    function _setAllowanceToLender() internal {
        uint256 allowance_ = IERC20Upgradeable(address(want)).allowance(
            address(this),
            address(cToken)
        );
        IERC20Upgradeable(address(want)).safeIncreaseAllowance(
            address(cToken),
            type(uint256).max - allowance_
        );
    }

    /*
     * @notice Calculate new Utilization after Deposit (when deposit has not been done yet).
     */
    function _getUtilizationAfterDeposit(
        uint256 extraAmount_
    ) internal view returns (uint256) {
        uint256 totalSupply_ = cToken.totalSupply();
        uint256 totalBorrow_ = cToken.totalBorrow();
        if (totalSupply_ == 0) {
            return 0;
        } else {
            return (totalBorrow_ * 1e18) / (totalSupply_ + extraAmount_);
        }
    }
}
