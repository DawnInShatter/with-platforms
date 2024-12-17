// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {AdminHelperUpgradeable} from "../helpers/AdminHelperUpgradeable.sol";
import {UniswapV3Utils} from "../libraries/UniswapV3Utils.sol";
import {SparkLibrary} from "../libraries/SparkLibrary.sol";

contract SimplifiedStrategyToSpark is AdminHelperUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice Uniswap Factory
    address public immutable UNISWAP_FACTORY;
    /// @notice The pool to deposit and withdraw through.
    address public immutable POOL;

    mapping(address => address) public investSPToken;

    error ErrorInvalidAddress();
    error ErrorNotMatchArray();
    error ErrorInvalidWantRouteLength();

    constructor(address sparkPool_, address uniswapV3Factory_) {
        if (sparkPool_ == address(0) || uniswapV3Factory_ == address(0)) {
            revert ErrorInvalidAddress();
        }

        POOL = sparkPool_;
        UNISWAP_FACTORY = uniswapV3Factory_;
    }

    function initialize() external initializer {
        __AdminHelper_init();
    }

    function addInvestSPToken(
        address want_,
        address spToken_
    ) external onlyAdmin {
        if (want_ == address(0) || spToken_ == address(0)) {
            revert ErrorInvalidAddress();
        }
        investSPToken[want_] = spToken_;
        _setAllowanceToThird(want_, POOL);
    }

    function wantBalance(address want_) public view returns (uint256) {
        return IERC20Upgradeable(want_).balanceOf(address(this));
    }

    function spTokenBalance(address want_) public view returns (uint256) {
        return SparkLibrary.spTokenBalance(investSPToken[want_]);
    }

    function getUnderlyingToken(address want_) public view returns (address) {
        return SparkLibrary.spTokenUnderlying(investSPToken[want_]);
    }

    function ethToToken(
        uint256 amount_,
        address[] memory tokensRouteRoute_,
        uint24[] memory fees_
    ) public view returns (uint256) {
        uint256 len_ = tokensRouteRoute_.length;
        if (len_ <= 1) {
            revert ErrorInvalidWantRouteLength();
        }
        if (fees_.length + 1 != len_) {
            revert ErrorNotMatchArray();
        }
        bytes memory tokensRoutePath_ = UniswapV3Utils.routeToPath(
            tokensRouteRoute_,
            fees_
        );
        return
            UniswapV3Utils.getAmountsOutByPath(
                UNISWAP_FACTORY,
                tokensRoutePath_,
                amount_
            );
    }

    function transferToAccount(
        address account_,
        address token_,
        uint256 amount_
    ) external onlyAdmin {
        require(account_ != address(0), "RECOVER_VAULT_ZERO");

        if (token_ == address(0)) {
            // Transfer replaced by call to prevent transfer gas amount issue
            (bool os, ) = account_.call{value: amount_}("");
            require(os, "RECOVER_TRANSFER_FAILED");
        } else {
            // safeTransfer comes from the overridden default implementation
            IERC20Upgradeable(token_).safeTransfer(account_, amount_);
        }
    }

    /**
     * @notice Invests the token.
     */
    function deposit(address want_, uint256 amount_) external {
        uint256 balance_ = IERC20Upgradeable(want_).balanceOf(address(this));
        if (balance_ > 0) {
            SparkLibrary.deposit(POOL, want_, amount_, address(this), 0);
        }
    }

    /**
     * @dev See {divest}.
     */
    function withdraw(address want_, uint256 amount_) external {
        SparkLibrary.withdraw(POOL, want_, amount_, address(this));
    }

    function _setAllowanceToThird(address want_, address third_) internal {
        uint256 allowance_ = IERC20Upgradeable(want_).allowance(
            address(this),
            third_
        );
        if (allowance_ < type(uint256).max / 2) {
            IERC20Upgradeable(want_).safeIncreaseAllowance(
                third_,
                type(uint256).max - allowance_
            );
        }
    }
}
