// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {TestCompoundV3} from "./TestCompoundV3.sol";

/**
 * @title Compound's CometRewards Contract
 * @notice Hold and claim token rewards
 * @author Compound
 */
contract TestCometRewards {
    struct RewardConfig {
        address token;
        uint64 rescaleFactor;
        bool shouldUpscale;
        // Note: We define new variables after existing variables to keep interface backwards-compatible
        uint256 multiplier;
    }

    struct RewardOwed {
        address token;
        uint owed;
    }

    uint256 public accruedAmount;

    /// @notice Reward token address per Comet instance
    mapping(address => RewardConfig) public rewardConfig;

    /// @notice Rewards claimed per Comet instance and user account
    mapping(address => mapping(address => uint)) public rewardsClaimed;

    mapping(address => uint256) public rewardAccrued;

    /** Custom events **/

    event RewardClaimed(
        address indexed src,
        address indexed recipient,
        address indexed token,
        uint256 amount
    );

    /** Custom errors **/

    error AlreadyConfigured(address);
    error InvalidUInt64(uint);
    error NotPermitted(address);
    error NotSupported(address);
    error TransferOutFailed(address, uint);

    constructor() {
        accruedAmount = 0;
    }

    /**
     * @notice Set the reward token for a Comet instance
     * @param comet The protocol instance
     * @param token The reward token address
     */
    function setRewardConfig(address comet, address token) external {
        if (rewardConfig[comet].token != address(0))
            revert AlreadyConfigured(comet);

        uint64 accrualScale = TestCompoundV3(comet).baseAccrualScale();
        uint8 tokenDecimals = IERC20MetadataUpgradeable(token).decimals();
        uint64 tokenScale = safe64(10 ** tokenDecimals);
        if (accrualScale > tokenScale) {
            rewardConfig[comet] = RewardConfig({
                token: token,
                rescaleFactor: accrualScale / tokenScale,
                shouldUpscale: false,
                multiplier: 0
            });
        } else {
            rewardConfig[comet] = RewardConfig({
                token: token,
                rescaleFactor: tokenScale / accrualScale,
                shouldUpscale: true,
                multiplier: 0
            });
        }
    }

    /**
     * @notice Withdraw tokens from the contract
     * @param token The reward token address
     * @param to Where to send the tokens
     * @param amount The number of tokens to withdraw
     */
    function withdrawToken(address token, address to, uint amount) external {
        doTransferOut(token, to, amount);
    }

    /**
     * @notice Calculates the amount of a reward token owed to an account
     * @param comet The protocol instance
     * @param account The account to check rewards for
     */
    function getRewardOwed(
        address comet,
        address account
    ) external returns (RewardOwed memory) {
        RewardConfig memory config = rewardConfig[comet];
        if (config.token == address(0)) revert NotSupported(comet);

        uint256 accrued = getRewardAccrued(comet, account, config);
        rewardAccrued[account] += accrued;

        return RewardOwed(config.token, accrued);
    }

    /**
     * @notice Claim rewards of token type from a comet instance to owner address
     * @param comet The protocol instance
     * @param src The owner to claim for
     * @param shouldAccrue Whether or not to call accrue first
     */
    function claim(address comet, address src, bool shouldAccrue) external {
        claimInternal(comet, src, src, shouldAccrue);
    }

    /**
     * @dev Claim to, assuming permitted
     */
    function claimInternal(
        address comet,
        address src,
        address to,
        bool
    ) internal {
        RewardConfig memory config = rewardConfig[comet];
        if (config.token == address(0)) revert NotSupported(comet);

        uint256 accrued = getRewardAccrued(comet, src, config);

        doTransferOut(config.token, to, accrued);
        rewardsClaimed[comet][src] += accrued;

        emit RewardClaimed(src, to, config.token, accrued);
    }

    /**
     * @dev Calculates the reward accrued for an account on a Comet deployment
     */
    function getRewardAccrued(
        address,
        address,
        RewardConfig memory config
    ) internal view returns (uint) {
        uint8 tokenDecimals = IERC20MetadataUpgradeable(config.token)
            .decimals();
        return accruedAmount * (10 ** tokenDecimals);
    }

    function updateAccruedAmount(uint256 amount) external {
        accruedAmount = amount;
    }

    /**
     * @dev Safe IERC20MetadataUpgradeable transfer out
     */
    function doTransferOut(address token, address to, uint amount) internal {
        bool success = IERC20MetadataUpgradeable(token).transfer(to, amount);
        if (!success) revert TransferOutFailed(to, amount);
    }

    /**
     * @dev Safe cast to uint64
     */
    function safe64(uint n) internal pure returns (uint64) {
        if (n > type(uint64).max) revert InvalidUInt64(n);
        return uint64(n);
    }
}
