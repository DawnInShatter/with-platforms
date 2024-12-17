// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ICurveStablePool} from "../interfaces/curve/ICurveStablePool.sol";

library CurveUtils {
    error ErrorReceivedNothing(uint256 amountIn, address outputToken);
    error ErrorSlippage(uint256 amountOut, uint256 amountMin);

    function getAmountsOut(
        address[] memory pools_,
        int128[2][] memory idRouterList_,
        uint256 amount_
    ) external view returns (uint256) {
        uint256 len_ = pools_.length;
        for (uint256 i = 0; i < len_; i++) {
            amount_ = ICurveStablePool(pools_[i]).get_dy(
                idRouterList_[i][0],
                idRouterList_[i][1],
                amount_
            );
        }
        // leave 1 wei in router for gas efficiency
        // https://github.com/curvefi/curve-router-ng/blob/9ab006ca848fc7f1995b6fbbecfecc1e0eb29e2a/contracts/Router.vy#L499
        return amount_ > 0 ? amount_ - 1 : amount_;
    }

    function stablePoolsSwapWithoutETH(
        address[] memory pools_,
        address[] memory tokenRouterList_,
        int128[2][] memory idRouterList_,
        uint256 amount_,
        uint256 amountMin_
    ) external returns (uint256) {
        uint256 len_ = pools_.length;
        address outputToken_ = address(0);
        for (uint256 i = 0; i < len_; i++) {
            outputToken_ = tokenRouterList_[i + 1];
            uint256 outputBalances_ = IERC20Upgradeable(outputToken_).balanceOf(
                address(this)
            );
            ICurveStablePool(pools_[i]).exchange(
                idRouterList_[i][0],
                idRouterList_[i][1],
                amount_,
                0
            );
            amount_ =
                IERC20Upgradeable(outputToken_).balanceOf(address(this)) -
                outputBalances_;
            if (amount_ == 0) {
                revert ErrorReceivedNothing(amount_, outputToken_);
            }
        }
        if (amount_ < amountMin_) {
            revert ErrorSlippage(amount_, amountMin_);
        }
        return amount_;
    }
}
