// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IUniswapV3SwapCallback} from "./IUniswapV3SwapCallback.sol";
import {UniswapV3Utils} from "../../libraries/UniswapV3Utils.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TestUniswapV3Pool {
    using SafeCast for uint256;
    using SafeCast for int256;

    address public immutable factory;
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable fee;

    Observation[65535] public observations;
    uint256 public observationIndex;

    struct Observation {
        // the block timestamp of the observation
        uint32 blockTimestamp;
        // the tick accumulator, i.e. tick * time elapsed since the pool was first initialized
        int56 tickCumulative;
        // the seconds per liquidity, i.e. seconds elapsed / max(1, liquidity) since the pool was first initialized
        uint160 secondsPerLiquidityCumulativeX128;
        // whether or not the observation is initialized
        bool initialized;
    }

    constructor(
        address factory_,
        address token0_,
        address token1_,
        uint24 fee_
    ) {
        factory = factory_;
        token0 = token0_;
        token1 = token1_;
        fee = fee_;
        observationIndex = 0;
    }

    function initObservations(
        Observation[] calldata observationList_
    ) external {
        require(observationList_.length == 2, "Only two observation");
        uint256 index_ = 0;
        uint32 blockTimestamp_ = observations[index_].blockTimestamp;
        for (uint256 i = 0; i < 2; i++) {
            require(
                blockTimestamp_ < observationList_[i].blockTimestamp,
                "Time error"
            );
            observations[index_] = observationList_[i];
            blockTimestamp_ = observationList_[i].blockTimestamp;
            index_ += 1;
        }
        observationIndex = 1;
    }

    /// @dev Get the pool's balance of token0
    /// @dev This function is gas optimized to avoid a redundant extcodesize check in addition to the returndatasize
    /// check
    function balance0() private view returns (uint256) {
        (bool success, bytes memory data) = token0.staticcall(
            abi.encodeWithSelector(IERC20.balanceOf.selector, address(this))
        );
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }

    /// @dev Get the pool's balance of token1
    /// @dev This function is gas optimized to avoid a redundant extcodesize check in addition to the returndatasize
    /// check
    function balance1() private view returns (uint256) {
        (bool success, bytes memory data) = token1.staticcall(
            abi.encodeWithSelector(IERC20.balanceOf.selector, address(this))
        );
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }

    function observe(
        uint32[] calldata secondsAgos
    )
        external
        view
        returns (
            int56[] memory tickCumulatives,
            uint160[] memory secondsPerLiquidityCumulativeX128s
        )
    {
        tickCumulatives = new int56[](secondsAgos.length);
        secondsPerLiquidityCumulativeX128s = new uint160[](secondsAgos.length);
        int24 tick = int24(
            (observations[1].tickCumulative - observations[0].tickCumulative) /
                int56(
                    int32(
                        observations[1].blockTimestamp -
                            observations[0].blockTimestamp
                    )
                )
        );
        uint256 len = secondsAgos.length;
        for (uint256 i = 0; i < len; i++) {
            if (secondsAgos[i] == 0) {
                (tickCumulatives[i], secondsPerLiquidityCumulativeX128s[i]) = (
                    observations[1].tickCumulative,
                    0
                );
                continue;
            }
            tickCumulatives[i] =
                observations[1].tickCumulative -
                int56(int32(secondsAgos[i])) *
                tick;
        }
    }

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1) {
        require(amountSpecified != 0, "AS");

        bool exactInput = amountSpecified > 0;
        int256 sign = -1;
        if (!exactInput) {
            amountSpecified = -amountSpecified;
            sign = 1;
        }
        // exactInput == true, 0 in to 1(true), 1 in to 0(false)
        // exactInput == false(out), 1 out to 0(true), 0 out to 1 (false)
        (amount0, amount1) = zeroForOne == exactInput
            ? (
                amountSpecified,
                sign *
                    UniswapV3Utils
                        .getQuote(
                            factory,
                            token0,
                            token1,
                            fee,
                            uint256(amountSpecified)
                        )
                        .toInt256()
            )
            : (
                sign *
                    UniswapV3Utils
                        .getQuote(
                            factory,
                            token1,
                            token0,
                            fee,
                            uint256(amountSpecified)
                        )
                        .toInt256(),
                amountSpecified
            );

        // do the transfers and collect payment
        if (zeroForOne) {
            if (amount1 < 0) safeTransfer(token1, recipient, uint256(-amount1));

            uint256 balance0Before = balance0();
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(
                amount0,
                amount1,
                data
            );
            require(balance0Before + uint256(amount0) <= balance0(), "IIA");
        } else {
            if (amount0 < 0) safeTransfer(token0, recipient, uint256(-amount0));

            uint256 balance1Before = balance1();
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(
                amount0,
                amount1,
                data
            );
            require(balance1Before + uint256(amount1) <= balance1(), "IIA");
        }
    }

    function safeTransfer(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TF"
        );
    }
}
