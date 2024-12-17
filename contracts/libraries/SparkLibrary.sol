// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import {IAToken} from "../interfaces/spark/IAToken.sol";
import {IPool} from "../interfaces/spark/IPool.sol";

library SparkLibrary {
    function deposit(
        address pool_,
        address asset_,
        uint256 amount_,
        address onBehalfOf_,
        uint16 referralCode_
    ) internal {
        IPool(pool_).supply(asset_, amount_, onBehalfOf_, referralCode_);
    }

    function withdraw(
        address pool_,
        address asset_,
        uint256 amount_,
        address to_
    ) internal returns (uint256) {
        return IPool(pool_).withdraw(asset_, amount_, to_);
    }

    function spTokenUnderlying(
        address spToken_
    ) internal view returns (address) {
        return IAToken(spToken_).UNDERLYING_ASSET_ADDRESS();
    }

    function spTokenBalance(address spToken_) internal view returns (uint256) {
        return IAToken(spToken_).balanceOf(address(this));
    }
}
