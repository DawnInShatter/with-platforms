// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {CometStructs} from "./CometStructs.sol";

interface ICometRewards {
    struct RewardConfig {
        address token;
        uint64 rescaleFactor;
        bool shouldUpscale;
        // Note: We define new variables after existing variables to keep interface backwards-compatible
        uint256 multiplier;
    }

    function rewardConfig(
        address comet
    ) external view returns (RewardConfig memory);

    function getRewardOwed(
        address comet,
        address account
    ) external returns (CometStructs.RewardOwed memory);

    function claim(address comet, address src, bool shouldAccrue) external;

    function claimTo(
        address comet,
        address src,
        address to,
        bool shouldAccrue
    ) external;
}
