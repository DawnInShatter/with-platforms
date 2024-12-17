// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {INonfungiblePositionManager} from "../interfaces/uniswap/INonfungiblePositionManager.sol";
import {IUniswapV3Factory} from "../interfaces/uniswap/IUniswapV3Factory.sol";
import {IUniswapV3Router} from "../interfaces/uniswap/IUniswapV3Router.sol";
import {IUniswapV3Pool} from "../interfaces/uniswap/IUniswapV3Pool.sol";
import {UniswapV3Utils} from "../libraries/UniswapV3Utils.sol";
import {OracleLibrary} from "../libraries/uniswap/OracleLibrary.sol";
import {TickMath} from "../libraries/uniswap/TickMath.sol";
import {TransferHelper} from "../libraries/uniswap/TransferHelper.sol";

contract WithUniswapV3 is Initializable, IERC721Receiver {
    INonfungiblePositionManager public immutable NONFUNGIBLE_POSITION_MANAGER;

    struct Deposit {
        address owner;
        uint128 liquidity;
        address token0;
        address token1;
    }

    /// @notice Uniswap V3 Router
    address public uniswapV3Router;
    IUniswapV3Factory public uniswapV3Factory;

    error ErrorInvalidRouteLength();
    error ErrorNotMatchArray();
    event EventIncreaseLiquidityWithNewPool(
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );
    event EventIncreaseLiquidity(
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );
    event EventDecreaseLiquidity(uint256 amount0, uint256 amount1);

    constructor(INonfungiblePositionManager nonfungiblePositionManager_) {
        NONFUNGIBLE_POSITION_MANAGER = nonfungiblePositionManager_;
    }

    function initialize(address routerAddr_) external initializer {
        uniswapV3Router = routerAddr_;
        uniswapV3Factory = IUniswapV3Factory(
            IUniswapV3Router(routerAddr_).factory()
        );
    }

    // Implementing `onERC721Received` so this contract can receive custody of erc721 tokens
    // Note that the operator is recorded as the owner of the deposited NFT
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external virtual returns (bytes4) {
        require(
            msg.sender == address(NONFUNGIBLE_POSITION_MANAGER),
            "not a univ3 nft"
        );
        return this.onERC721Received.selector;
    }

    function setApprove(address token_, address contract_) external {
        TransferHelper.safeApprove(token_, contract_, type(uint256).max);
    }

    function increaseLiquidityWithNewPool(
        UniswapV3Utils.LiquidityParams memory lqParams_,
        uint256 amount0ToMint_,
        uint256 amount1ToMint_
    ) external {
        require(lqParams_.token0 < lqParams_.token1);
        // Approve the position manager
        TransferHelper.safeApprove(
            lqParams_.token0,
            address(NONFUNGIBLE_POSITION_MANAGER),
            amount0ToMint_
        );
        TransferHelper.safeApprove(
            lqParams_.token1,
            address(NONFUNGIBLE_POSITION_MANAGER),
            amount1ToMint_
        );

        // create pool
        UniswapV3Utils.createPool(
            address(NONFUNGIBLE_POSITION_MANAGER),
            lqParams_.token0,
            lqParams_.token1,
            lqParams_.fee,
            amount0ToMint_,
            amount1ToMint_
        );
        (
            uint256 tokenId_,
            uint128 liquidity_,
            uint256 amount0_,
            uint256 amount1_
        ) = UniswapV3Utils.increaseLiquidityWithNew(
                address(NONFUNGIBLE_POSITION_MANAGER),
                lqParams_,
                amount0ToMint_,
                amount1ToMint_
            );
        emit EventIncreaseLiquidityWithNewPool(
            tokenId_,
            liquidity_,
            amount0_,
            amount1_
        );
    }

    function increaseLiquidityToPool(
        UniswapV3Utils.LiquidityParams memory lqParams_,
        uint256 amount0ToMint_,
        uint256 amount1ToMint_
    )
        external
        returns (
            uint256 tokenId_,
            uint128 liquidity_,
            uint256 amount0_,
            uint256 amount1_
        )
    {
        require(lqParams_.token0 < lqParams_.token1);
        // Approve the position manager
        TransferHelper.safeApprove(
            lqParams_.token0,
            address(NONFUNGIBLE_POSITION_MANAGER),
            amount0ToMint_
        );
        TransferHelper.safeApprove(
            lqParams_.token1,
            address(NONFUNGIBLE_POSITION_MANAGER),
            amount1ToMint_
        );

        return
            UniswapV3Utils.increaseLiquidityWithNew(
                address(NONFUNGIBLE_POSITION_MANAGER),
                lqParams_,
                amount0ToMint_,
                amount1ToMint_
            );
    }

    function increaseLiquidityToPool(
        uint256 lpTokenId_,
        uint256 amountAdd0_,
        uint256 amountAdd1_
    ) external {
        (address token0_, address token1_, ) = UniswapV3Utils.getPositionsData(
            address(NONFUNGIBLE_POSITION_MANAGER),
            lpTokenId_
        );
        // Approve the position manager
        TransferHelper.safeApprove(
            token0_,
            address(NONFUNGIBLE_POSITION_MANAGER),
            amountAdd0_
        );
        TransferHelper.safeApprove(
            token1_,
            address(NONFUNGIBLE_POSITION_MANAGER),
            amountAdd1_
        );

        (
            uint128 liquidity_,
            uint256 amount0_,
            uint256 amount1_
        ) = UniswapV3Utils.increaseLiquidity(
                address(NONFUNGIBLE_POSITION_MANAGER),
                lpTokenId_,
                amountAdd0_,
                amountAdd1_,
                1000000
            );
        emit EventIncreaseLiquidity(liquidity_, amount0_, amount1_);
    }

    /// @notice Collects the fees associated with provided liquidity
    /// @dev The contract must hold the erc721 token before it can collect fees
    /// @param lpTokenId_ The id of the erc721 token
    function collectAllFees(uint256 lpTokenId_) external {
        (uint256 amount0_, uint256 amount1_) = UniswapV3Utils
            .collectLiquidityFees(
                address(NONFUNGIBLE_POSITION_MANAGER),
                lpTokenId_
            );
        (address token0_, address token1_, ) = UniswapV3Utils.getPositionsData(
            address(NONFUNGIBLE_POSITION_MANAGER),
            lpTokenId_
        );
        // send collected fees to owner
        TransferHelper.safeTransfer(token0_, msg.sender, amount0_);
        TransferHelper.safeTransfer(token1_, msg.sender, amount1_);
    }

    /// @notice A function that decreases the current liquidity.
    function decreaseLiquidityToPool(
        uint256 lpTokenId_,
        uint128 liquidity_
    ) external {
        (uint256 amount0_, uint256 amount1_) = UniswapV3Utils.decreaseLiquidity(
            address(NONFUNGIBLE_POSITION_MANAGER),
            lpTokenId_,
            liquidity_
        );
        emit EventDecreaseLiquidity(amount0_, amount1_);
    }

    function setUniswapRouter(address addr_) external {
        uniswapV3Router = addr_;
    }

    function setUniswapFactory() external {
        uniswapV3Factory = IUniswapV3Factory(
            IUniswapV3Router(uniswapV3Router).factory()
        );
    }

    function getTokensRouteEncodePath(
        address[] memory tokensRoute_,
        uint24[] memory fees_
    ) external pure returns (bytes memory path) {
        return _getTokensRouteEncodePath(tokensRoute_, fees_);
    }

    function _getTokensRouteEncodePath(
        address[] memory tokensRoute_,
        uint24[] memory fees_
    ) internal pure returns (bytes memory path) {
        uint256 len_ = tokensRoute_.length;
        if (len_ <= 1) {
            revert ErrorInvalidRouteLength();
        }
        if (fees_.length + 1 != len_) {
            revert ErrorNotMatchArray();
        }
        return UniswapV3Utils.routeToPath(tokensRoute_, fees_);
    }

    function swapTokensByUniswap(address token_, bytes memory path_) external {
        _swapTokensByUniswap(token_, path_);
    }

    function _swapTokensByUniswap(address token_, bytes memory path_) internal {
        uint256 balance_ = IERC20Upgradeable(token_).balanceOf(address(this));
        if (balance_ > 0) {
            UniswapV3Utils.swap(uniswapV3Router, path_, balance_);
        }
    }

    function getUniswapAmountsOut(
        bytes memory path_,
        uint256 amount_
    ) external view returns (uint256) {
        return _getUniswapAmountsOut(path_, amount_);
    }

    function _getUniswapAmountsOut(
        bytes memory path_,
        uint256 amount_
    ) internal view returns (uint256) {
        (address[] memory route_, uint24[] memory fees_) = UniswapV3Utils
            .pathToRouteAndFees(path_);
        uint256 len_ = fees_.length;
        if (len_ < 1) revert ErrorInvalidRouteLength();
        for (uint256 i = 0; i < len_; i++) {
            amount_ = _getQuote(route_[i], route_[i + 1], fees_[i], amount_);
        }
        return amount_;
    }

    function _getQuote(
        address tokenIn_,
        address tokenOut_,
        uint24 fee_,
        uint256 amountIn_
    ) internal view returns (uint256) {
        address pool_ = uniswapV3Factory.getPool(tokenIn_, tokenOut_, fee_);
        (int24 tick_, ) = OracleLibrary.consult(pool_, 60);
        return
            OracleLibrary.getQuoteAtTick(
                tick_,
                uint128(amountIn_),
                tokenIn_,
                tokenOut_
            );
    }

    function swapToOwner(address token_, uint256 amount_) external {
        // send collected fees to owner
        TransferHelper.safeTransfer(token_, msg.sender, amount_);
    }
}
