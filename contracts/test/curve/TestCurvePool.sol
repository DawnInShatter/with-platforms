// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract TestCurvePool is Initializable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    TokenData public token0Data;
    TokenData public token1Data;

    struct TokenData {
        bool isNative;
        address token;
        int128 tokenId;
        uint256 baseAmount;
    }

    receive() external payable {}

    function initialize(
        TokenData memory token0Data_,
        TokenData memory token1Data_
    ) public initializer {
        token0Data = token0Data_;
        token1Data = token1Data_;
    }

    function exchange(
        int128 from_,
        int128 to_,
        uint256 fromAmount_,
        uint256 minToAmount_
    ) external payable {
        TokenData memory fromTokenData_ = token1Data;
        TokenData memory toTokenData_ = token0Data;
        if (from_ == token0Data.tokenId && to_ == token1Data.tokenId) {
            fromTokenData_ = token0Data;
            toTokenData_ = token1Data;
        }
        if (fromTokenData_.isNative) {
            require(msg.value == fromAmount_, "Msg.value is not enough");
        }
        uint256 toAmount_ = _getAmountOut(
            fromTokenData_.token,
            fromAmount_,
            fromTokenData_.isNative ? fromAmount_ : 0
        );
        if (!fromTokenData_.isNative) {
            IERC20Upgradeable(fromTokenData_.token).safeTransferFrom(
                msg.sender,
                address(this),
                fromAmount_
            );
        }
        if (!toTokenData_.isNative) {
            IERC20Upgradeable(toTokenData_.token).safeTransfer(
                msg.sender,
                toAmount_
            );
        } else {
            (bool success_, ) = payable(msg.sender).call{value: toAmount_}("");
            require(success_, "Fail to transfer native token");
        }

        require(toAmount_ >= minToAmount_, "Amount is too small");
    }

    function getToken1Balance() public view returns (uint256) {
        uint256 balance_ = token1Data.baseAmount;
        if (token1Data.isNative) {
            balance_ += address(this).balance;
        } else {
            balance_ += IERC20Upgradeable(token1Data.token).balanceOf(
                address(this)
            );
        }
        return balance_;
    }

    function getToken0Balance() public view returns (uint256) {
        uint256 balance_ = token0Data.baseAmount;
        if (token0Data.isNative) {
            balance_ += address(this).balance;
        } else {
            balance_ += IERC20Upgradeable(token0Data.token).balanceOf(
                address(this)
            );
        }
        return balance_;
    }

    function get_dy(
        int128 from_,
        int128 to_,
        uint256 fromAmount_
    ) external view returns (uint256 toAmount_) {
        TokenData memory fromTokenData_ = token1Data;
        TokenData memory toTokenData_ = token0Data;
        if (from_ == token0Data.tokenId && to_ == token1Data.tokenId) {
            fromTokenData_ = token0Data;
            toTokenData_ = token1Data;
        }
        toAmount_ = _getAmountOut(fromTokenData_.token, fromAmount_, 0);
    }

    function setToken0BaseAmount(uint256 newAmount_) external {
        token0Data.baseAmount = newAmount_;
    }

    function setToken1BaseAmount(uint256 newAmount_) external {
        token1Data.baseAmount = newAmount_;
    }

    function migrateToken(
        address token_,
        address to_,
        uint256 amount_
    ) external {
        if (token_ == address(0)) {
            (bool success_, ) = payable(to_).call{value: amount_}("");
            require(success_, "Fail to transfer native token");
        } else {
            IERC20Upgradeable(token_).safeTransfer(to_, amount_);
        }
    }

    function _getAmountOut(
        address fromToken_,
        uint256 fromAmount_,
        uint256 receiveAmount_
    ) internal view returns (uint256) {
        if (fromToken_ == token0Data.token) {
            return _getAmountOutFrom0To1(fromAmount_, receiveAmount_);
        } else {
            return _getAmountOutFrom1To0(fromAmount_, receiveAmount_);
        }
    }

    function _getAmountOutFrom0To1(
        uint256 fromAmount_,
        uint256 receivedAmount_
    ) internal view returns (uint256) {
        uint256 reserveToken0_ = getToken0Balance();
        reserveToken0_ -= receivedAmount_;
        uint256 reserveToken1_ = getToken1Balance();
        return
            reserveToken1_ -
            (reserveToken0_ * reserveToken1_) /
            (reserveToken0_ + fromAmount_);
    }

    function _getAmountOutFrom1To0(
        uint256 fromAmount_,
        uint256 receivedAmount_
    ) internal view returns (uint256) {
        uint256 reserveToken1_ = getToken1Balance();
        reserveToken1_ -= receivedAmount_;
        uint256 reserveToken0_ = getToken0Balance();
        return
            reserveToken0_ -
            (reserveToken0_ * reserveToken1_) /
            (reserveToken1_ + fromAmount_);
    }
}
