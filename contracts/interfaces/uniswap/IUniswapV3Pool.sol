// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import {IUniswapV3PoolImmutables} from "./pool/IUniswapV3PoolImmutables.sol";
import {IUniswapV3PoolState} from "./pool/IUniswapV3PoolState.sol";
import {IUniswapV3PoolDerivedState} from "./pool/IUniswapV3PoolDerivedState.sol";
import {IUniswapV3PoolActions} from "./pool/IUniswapV3PoolActions.sol";

/// @title The interface for a Uniswap V3 Pool
/// @notice A Uniswap pool facilitates swapping and automated market making between any two assets that strictly conform
/// to the ERC20 specification
/// @dev The pool interface is broken up into many smaller pieces
interface IUniswapV3Pool is
    IUniswapV3PoolImmutables,
    IUniswapV3PoolState,
    IUniswapV3PoolDerivedState,
    IUniswapV3PoolActions
{

}
