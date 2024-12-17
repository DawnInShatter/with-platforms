// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {AdminHelperUpgradeable} from "../../helpers/AdminHelperUpgradeable.sol";
import {DataTypesV3} from "../../interfaces/aave/DataTypesV3.sol";
import {ITestAToken} from "./ITestAToken.sol";

contract TestAavePool is AdminHelperUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice asset => atoken
    mapping(address => ITestAToken) public tokenToAToken;

    // Records a deposit made by a user
    event EventSupply(
        address indexed sender,
        uint256 amount,
        uint16 referralCode
    );
    event EventWithdraw(
        address indexed sender,
        uint256 amount,
        uint256 withdrawAmount
    );

    function initialize() public initializer {
        __AdminHelper_init();
    }

    function getPool() public view returns (address) {
        return address(this);
    }

    function getReserveDataExtended(
        address asset_
    ) public view returns (DataTypesV3.ReserveData memory) {
        DataTypesV3.ReserveData memory data_ = tokenToAToken[asset_]
            .getReserveDataExtend();
        data_.interestRateStrategyAddress = address(this);
        return data_;
    }

    function getReserveData(
        address asset_
    ) public view returns (DataTypesV3.ReserveDataLegacy memory) {
        DataTypesV3.ReserveDataLegacy memory data_ = tokenToAToken[asset_]
            .getReserveData();
        data_.interestRateStrategyAddress = address(this);
        return data_;
    }

    function calculateInterestRates(
        DataTypesV3.CalculateInterestRatesParams calldata params_
    ) external view returns (uint256, uint256, uint256) {
        return tokenToAToken[params_.reserve].calculateInterestRates(params_);
    }

    function supply(
        address asset_,
        uint256 amount_,
        address behalfof,
        uint16 referralCode_
    ) external {
        require(amount_ != 0, "ZERO_DEPOSIT");
        IERC20Upgradeable(asset_).safeTransferFrom(
            msg.sender,
            address(tokenToAToken[asset_]),
            amount_
        );

        tokenToAToken[asset_].supply(
            msg.sender,
            amount_,
            behalfof,
            referralCode_
        );
        emit EventSupply(msg.sender, amount_, referralCode_);
    }

    function withdraw(
        address asset_,
        uint256 amount_,
        address to_
    ) external returns (uint256) {
        if (amount_ == 0) {
            return 0;
        }
        uint256 amountWithDraw_ = tokenToAToken[asset_].withdraw(
            amount_,
            msg.sender,
            to_
        );

        emit EventWithdraw(msg.sender, amount_, amountWithDraw_);

        return amountWithDraw_;
    }

    function addAToken(address asset_, address aToken_) external onlyAdmin {
        require(aToken_ != address(0), "Invalid zero address");
        tokenToAToken[asset_] = ITestAToken(aToken_);
    }
}
