// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {CometStructs} from "./CometStructs.sol";

interface IComet {
    function baseScale() external view returns (uint256);

    function supply(address asset, uint256 amount) external;

    function withdraw(address asset, uint256 amount) external;

    function getSupplyRate(uint256 utilization) external view returns (uint256);

    function getBorrowRate(uint256 utilization) external view returns (uint256);

    function getAssetInfoByAddress(
        address asset
    ) external view returns (CometStructs.AssetInfo memory);

    function getAssetInfo(
        uint8 i
    ) external view returns (CometStructs.AssetInfo memory);

    function getPrice(address priceFeed) external view returns (uint128);

    function userBasic(
        address
    ) external view returns (CometStructs.UserBasic memory);

    function totalsBasic()
        external
        view
        returns (CometStructs.TotalsBasic memory);

    function userCollateral(
        address,
        address
    ) external view returns (CometStructs.UserCollateral memory);

    function baseTokenPriceFeed() external view returns (address);

    function numAssets() external view returns (uint8);

    function getUtilization() external view returns (uint256);

    function baseTrackingSupplySpeed() external view returns (uint256);

    function baseTrackingBorrowSpeed() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function totalBorrow() external view returns (uint256);

    function baseIndexScale() external pure returns (uint64);

    function totalsCollateral(
        address asset
    ) external view returns (CometStructs.TotalsCollateral memory);

    function baseMinForRewards() external view returns (uint256);

    function baseToken() external view returns (address);

    function getCollateralReserves(
        address asset
    ) external view returns (uint256);

    function getReserves() external view returns (int256);

    function balanceOf(address account) external view returns (uint256);

    function borrowBalanceOf(address account) external view returns (uint256);
}
