// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC4626Upgradeable.sol";

interface IStakedUSDe is IERC4626Upgradeable {
    struct UserCooldown {
        uint104 cooldownEnd;
        uint152 underlyingAmount;
    }

    function cooldowns(
        address account
    ) external view returns (UserCooldown memory);

    function cooldownAssets(uint256 assets) external returns (uint256 shares);

    function cooldownShares(uint256 shares) external returns (uint256 assets);

    function unstake(address receiver) external;

    function getUnvestedAmount() external view returns (uint256);
}
