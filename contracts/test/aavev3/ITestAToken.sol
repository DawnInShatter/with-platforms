// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {DataTypesV3} from "../../interfaces/aave/DataTypesV3.sol";
import {IAToken} from "../../interfaces/aave/IAtoken.sol";

interface ITestAToken is IAToken {
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);

    function getReserveDataExtend()
        external
        view
        returns (DataTypesV3.ReserveData memory);

    function getReserveData()
        external
        view
        returns (DataTypesV3.ReserveDataLegacy memory);

    function calculateInterestRates(
        DataTypesV3.CalculateInterestRatesParams calldata
    ) external view returns (uint256, uint256, uint256);

    function supply(
        address account_,
        uint256 amount_,
        address behalfof,
        uint16 referralCode_
    ) external;

    function withdraw(
        uint256 amount_,
        address account_,
        address to_
    ) external returns (uint256);
}
