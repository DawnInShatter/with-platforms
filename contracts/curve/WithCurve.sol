// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {CurveUtils} from "../libraries/CurveUtils.sol";

contract WithCurve is Initializable {
    function getAmountsOut(
        address[] memory pools_,
        int128[2][] memory idRouterList_,
        uint256 amount_
    ) external view returns (uint256) {
        return CurveUtils.getAmountsOut(pools_, idRouterList_, amount_);
    }

    function stablePoolsSwapWithoutETH(
        address[] memory pools_,
        address[] memory tokenRouterList_,
        int128[2][] memory idRouterList_,
        uint256 amount_,
        uint256 amountMin_
    ) external returns (uint256) {
        return
            CurveUtils.stablePoolsSwapWithoutETH(
                pools_,
                tokenRouterList_,
                idRouterList_,
                amount_,
                amountMin_
            );
    }
}
