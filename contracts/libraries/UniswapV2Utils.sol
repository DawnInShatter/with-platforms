// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV2Router02} from "../interfaces/uniswap/IUniswapV2Router.sol";

library UniswapV2Utils {
    error ErrorInvalidPath();

    function getAmountsOutByPath(
        address uniswapV2Router_,
        uint256 amountIn_,
        address[] memory path_
    ) internal view returns (uint256) {
        uint256[] memory amounts_ = IUniswapV2Router02(uniswapV2Router_)
            .getAmountsOut(amountIn_, path_);
        return amounts_[amounts_.length - 1];
    }

    function swap(
        address uniswapV2Router_,
        uint256 amountIn_,
        address[] memory path_,
        address to_
    ) internal returns (uint256[] memory amounts) {
        amounts = IUniswapV2Router02(uniswapV2Router_).swapExactTokensForTokens(
            amountIn_,
            0,
            path_,
            to_,
            type(uint256).max
        );
    }

    function swap(
        address uniswapV2Router_,
        uint256 amountIn_,
        uint256 amountOutMin_,
        address[] memory path_,
        address to_
    ) internal returns (uint256[] memory amounts) {
        amounts = IUniswapV2Router02(uniswapV2Router_).swapExactTokensForTokens(
            amountIn_,
            amountOutMin_,
            path_,
            to_,
            type(uint256).max
        );
    }
}
