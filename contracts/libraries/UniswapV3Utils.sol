// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IUniswapV3Router} from "../interfaces/uniswap/IUniswapV3Router.sol";
import {IUniswapV3Pool} from "../interfaces/uniswap/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "../interfaces/uniswap/IUniswapV3Factory.sol";
import {INonfungiblePositionManager} from "../interfaces/uniswap/INonfungiblePositionManager.sol";
import {TickMath} from "./uniswap/TickMath.sol";
import {OracleLibrary} from "./uniswap/OracleLibrary.sol";
import {Path} from "./Path.sol";

library UniswapV3Utils {
    using Path for bytes;
    uint256 public constant MAX_BPS = 1000000;

    error ErrorInvalidPath();

    // Convert encoded path to token route
    function pathToRoute(
        bytes memory path_
    ) internal pure returns (address[] memory) {
        uint256 numPools_ = path_.numPools();
        address[] memory route_ = new address[](numPools_ + 1);
        for (uint256 i; i < numPools_; i++) {
            (address tokenA_, address tokenB_, ) = path_.decodeFirstPool();
            route_[i] = tokenA_;
            route_[i + 1] = tokenB_;
            path_ = path_.skipToken();
        }
        return route_;
    }

    // Convert encoded path to token route and fee
    function pathToRouteAndFees(
        bytes memory path_
    ) internal pure returns (address[] memory, uint24[] memory) {
        uint256 numPools_ = path_.numPools();
        address[] memory route_ = new address[](numPools_ + 1);
        uint24[] memory fees_ = new uint24[](numPools_);
        for (uint256 i; i < numPools_; i++) {
            (address tokenA_, address tokenB_, uint24 fee_) = path_
                .decodeFirstPool();
            route_[i] = tokenA_;
            route_[i + 1] = tokenB_;
            path_ = path_.skipToken();
            fees_[i] = fee_;
        }
        return (route_, fees_);
    }

    // Convert token route to encoded path
    // uint24 type for fees so path is packed tightly
    function routeToPath(
        address[] memory route_,
        uint24[] memory fees_
    ) internal pure returns (bytes memory path_) {
        path_ = abi.encodePacked(route_[0]);
        uint256 feeLen_ = fees_.length;
        for (uint256 i = 0; i < feeLen_; i++) {
            path_ = abi.encodePacked(path_, fees_[i], route_[i + 1]);
        }
    }

    function getAmountsOutByPath(
        address uniswapFactory_,
        bytes memory path_,
        uint256 amount_
    ) internal view returns (uint256) {
        (address[] memory route_, uint24[] memory fees_) = pathToRouteAndFees(
            path_
        );
        uint256 len_ = fees_.length;
        if (len_ < 1) revert ErrorInvalidPath();
        for (uint256 i = 0; i < len_; i++) {
            amount_ = getQuote(
                uniswapFactory_,
                route_[i],
                route_[i + 1],
                fees_[i],
                amount_
            );
        }
        return amount_;
    }

    function getQuote(
        address uniswapFactory_,
        address tokenIn_,
        address tokenOut_,
        uint24 fee_,
        uint256 amountIn_
    ) internal view returns (uint256) {
        address pool_ = IUniswapV3Factory(uniswapFactory_).getPool(
            tokenIn_,
            tokenOut_,
            fee_
        );
        (int24 tick_, ) = OracleLibrary.consult(pool_, 60);
        return
            OracleLibrary.getQuoteAtTick(
                tick_,
                uint128(amountIn_),
                tokenIn_,
                tokenOut_
            );
    }

    // Swap along an encoded path using known amountIn
    function swap(
        address router_,
        bytes memory path_,
        uint256 amountIn_
    ) internal returns (uint256) {
        IUniswapV3Router.ExactInputParams memory params_ = IUniswapV3Router
            .ExactInputParams({
                path: path_,
                recipient: address(this),
                amountIn: amountIn_,
                amountOutMinimum: 0
            });
        return IUniswapV3Router(router_).exactInput(params_);
    }

    // Swap along an encoded path using known amountIn, specified recipient
    function swap(
        address router_,
        bytes memory path_,
        uint256 amountIn_,
        address to_
    ) internal returns (uint256) {
        IUniswapV3Router.ExactInputParams memory params_ = IUniswapV3Router
            .ExactInputParams({
                path: path_,
                recipient: to_,
                amountIn: amountIn_,
                amountOutMinimum: 0
            });
        return IUniswapV3Router(router_).exactInput(params_);
    }

    // Swap along a token route using known fees and amountIn
    function swap(
        address router_,
        address[] memory route_,
        uint24[] memory fee_,
        uint256 amountIn_
    ) internal returns (uint256) {
        return swap(router_, routeToPath(route_, fee_), amountIn_);
    }

    function isValidTick(
        address pool_,
        int24 tick_
    ) internal view returns (bool) {
        int24 tickSpacing_ = getTickSpacing(pool_);
        return int24(tick_ / tickSpacing_) * tickSpacing_ == tick_;
    }

    function getTickSpacing(address pool_) internal view returns (int24) {
        return IUniswapV3Pool(pool_).tickSpacing();
    }

    /// @notice Calls the mint function defined in periphery, mints the same amount of each token.
    /// @param positionManager_ The address of NonfungiblePositionManager
    /// @param token0_ The address of the token0 for a specific pool
    /// @param token1_ The address of the token1 for a specific pool
    /// @param fee_ The fee associated with the pool,1000/3000/5000
    /// @param amount0ToMint_ The address of NonfungiblePositionManager
    /// @param amount1ToMint_ The address of NonfungiblePositionManager
    function createPool(
        address positionManager_,
        address token0_,
        address token1_,
        uint24 fee_,
        uint256 amount0ToMint_,
        uint256 amount1ToMint_
    ) internal returns (address pool_) {
        require(token0_ < token1_);
        uint160 sqrtPriceX96_ = uint160(
            Math.sqrt((amount1ToMint_ * 2 ** 96) / amount0ToMint_) * 2 ** 48
        );
        pool_ = INonfungiblePositionManager(positionManager_)
            .createAndInitializePoolIfNecessary(
                token0_,
                token1_,
                fee_,
                sqrtPriceX96_
            );
    }

    struct LiquidityParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 slippage; // 1000000 = 100%
    }

    /// @notice Calls the mint function defined in periphery, mints the same amount of each token.
    /// @param positionManager_ The address of NonfungiblePositionManager
    /// @param lqParams_ LiquidityParams
    /// @param amount0ToMint_ The address of NonfungiblePositionManager
    /// @param amount1ToMint_ The address of NonfungiblePositionManager
    /// @return tokenId_ The id of the newly minted ERC721
    /// @return liquidity_ The amount of liquidity for the position
    /// @return amount0_ The amount of token0
    /// @return amount1_ The amount of token1
    function increaseLiquidityWithNew(
        address positionManager_,
        LiquidityParams memory lqParams_,
        uint256 amount0ToMint_,
        uint256 amount1ToMint_
    )
        internal
        returns (
            uint256 tokenId_,
            uint128 liquidity_,
            uint256 amount0_,
            uint256 amount1_
        )
    {
        require(lqParams_.token0 < lqParams_.token1);
        address pool_ = IUniswapV3Factory(
            INonfungiblePositionManager(positionManager_).factory()
        ).getPool(lqParams_.token0, lqParams_.token1, lqParams_.fee);
        require(isValidTick(pool_, lqParams_.tickLower), "Invalid tick lower");
        require(isValidTick(pool_, lqParams_.tickUpper), "Invalid tick upper");
        // The values for tickLower and tickUpper may not work for all tick spacings.
        // Setting amount0Min and amount1Min to 0 is unsafe.
        INonfungiblePositionManager.MintParams
            memory params_ = INonfungiblePositionManager.MintParams({
                token0: lqParams_.token0,
                token1: lqParams_.token1,
                fee: lqParams_.fee,
                tickLower: lqParams_.tickLower,
                tickUpper: lqParams_.tickUpper,
                amount0Desired: amount0ToMint_,
                amount1Desired: amount1ToMint_,
                amount0Min: (amount0ToMint_ * (MAX_BPS - lqParams_.slippage)) /
                    MAX_BPS,
                amount1Min: (amount1ToMint_ * (MAX_BPS - lqParams_.slippage)) /
                    MAX_BPS,
                recipient: address(this),
                deadline: block.timestamp
            });

        (
            tokenId_,
            liquidity_,
            amount0_,
            amount1_
        ) = INonfungiblePositionManager(positionManager_).mint(params_);
    }

    /// @notice Increases liquidity in the current range
    /// @dev Pool must be initialized already to add liquidity
    /// @param positionManager_ The address of NonfungiblePositionManager
    /// @param lpTokenId_ The ID of the token for which liquidity was increased
    /// @param amountAdd0_ The amount of token0 to be spent
    /// @param amountAdd1_ The amount of token1 to be spent
    /// @return liquidity_ The amount by which liquidity for the NFT position was increased
    /// @return amount0_ The amount of token0 that was paid for the increase in liquidity
    /// @return amount1_ The amount of token1 that was paid for the increase in liquidity
    function increaseLiquidity(
        address positionManager_,
        uint256 lpTokenId_,
        uint256 amountAdd0_,
        uint256 amountAdd1_,
        uint256 slippage_
    )
        internal
        returns (uint128 liquidity_, uint256 amount0_, uint256 amount1_)
    {
        INonfungiblePositionManager.IncreaseLiquidityParams
            memory params_ = INonfungiblePositionManager
                .IncreaseLiquidityParams({
                    tokenId: lpTokenId_,
                    amount0Desired: amountAdd0_,
                    amount1Desired: amountAdd1_,
                    amount0Min: (amountAdd0_ * (MAX_BPS - slippage_)) / MAX_BPS,
                    amount1Min: (amountAdd1_ * (MAX_BPS - slippage_)) / MAX_BPS,
                    deadline: block.timestamp
                });

        (liquidity_, amount0_, amount1_) = INonfungiblePositionManager(
            positionManager_
        ).increaseLiquidity(params_);
    }

    /// @notice A function that decreases the current liquidity.
    /// @param positionManager_ The address of NonfungiblePositionManager
    /// @param lpTokenId_ The id of the erc721 token
    /// @param liquidity_ The amount by which liquidity will be decreased
    /// @return amount0_ The amount of token0 accounted to the position's tokens owed
    /// @return amount1_ The amount of token1 accounted to the position's tokens owed
    function decreaseLiquidity(
        address positionManager_,
        uint256 lpTokenId_,
        uint128 liquidity_
    ) internal returns (uint256 amount0_, uint256 amount1_) {
        // amount0Min and amount1Min are price slippage checks
        // if the amount received after burning is not greater than these minimums, transaction will fail
        INonfungiblePositionManager.DecreaseLiquidityParams
            memory params_ = INonfungiblePositionManager
                .DecreaseLiquidityParams({
                    tokenId: lpTokenId_,
                    liquidity: liquidity_,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                });

        (amount0_, amount1_) = INonfungiblePositionManager(positionManager_)
            .decreaseLiquidity(params_);
    }

    /// @notice Collects the fees associated with provided liquidity
    /// @dev The contract must hold the erc721 token before it can collect fees
    /// @param positionManager_ The address of NonfungiblePositionManager
    /// @param lpTokenId_ The id of the erc721 token
    /// @return amount0_ The amount of fees collected in token0
    /// @return amount1_ The amount of fees collected in token1
    function collectLiquidityFees(
        address positionManager_,
        uint256 lpTokenId_
    ) internal returns (uint256 amount0_, uint256 amount1_) {
        // Caller must own the ERC721 position, meaning it must be a deposit
        // set amount0Max and amount1Max to type(uint128).max to collect all fees
        // alternatively can set recipient to msg.sender and avoid another transaction in `sendToOwner`
        INonfungiblePositionManager.CollectParams
            memory params_ = INonfungiblePositionManager.CollectParams({
                tokenId: lpTokenId_,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        (amount0_, amount1_) = INonfungiblePositionManager(positionManager_)
            .collect(params_);
    }

    function getPositionsData(
        address positionManager_,
        uint256 lpTokenId_
    )
        internal
        view
        returns (address token0_, address token1_, uint128 liquidity_)
    {
        (
            ,
            ,
            token0_,
            token1_,
            ,
            ,
            ,
            liquidity_,
            ,
            ,
            ,

        ) = INonfungiblePositionManager(positionManager_).positions(lpTokenId_);
    }
}
