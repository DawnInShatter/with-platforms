// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

/**
 * @title AaveV3's RewardController Contract
 * @notice Hold and claim token rewards
 */
contract TestAaveRewardsController {
    struct RewardConfig {
        address rwdToken;
        uint256 amount;
    }

    mapping(address => RewardConfig[]) public aTokenRewardsConfig;
    address[] public rewardList;
    mapping(address => uint256) public rwdTokenIdx;

    /** Custom errors **/
    error TransferOutFailed(address, uint);

    event RewardsClaimed(
        address indexed user,
        address indexed reward,
        address indexed to,
        address claimer,
        uint256 amount
    );

    /**
     * @dev Returns the list of available reward token addresses of an incentivized asset
     * @param asset_ The incentivized asset
     * @return List of rewards addresses of the input asset
     **/
    function getRewardsByAsset(
        address asset_
    ) external view returns (address[] memory) {
        uint256 len_ = aTokenRewardsConfig[asset_].length;
        address[] memory tokenList_ = new address[](len_);
        for (uint256 i = 0; i < len_; i++) {
            tokenList_[i] = aTokenRewardsConfig[asset_][i].rwdToken;
        }
        return tokenList_;
    }

    /**
     * @dev Returns the list of available reward addresses
     * @return List of rewards supported in this contract
     **/
    function getRewardsList() external view returns (address[] memory) {
        return rewardList;
    }

    /**
     * @dev Claims all reward for msg.sender, on all the assets of the pool, accumulating the pending rewards
     * @param assets_ The list of assets to check eligible distributions before claiming rewards
     * @return rewardsList_ List of addresses of the reward tokens
     * @return claimedAmounts_ List that contains the claimed amount per reward, following same order as "rewardsList"
     **/
    function claimAllRewardsToSelf(
        address[] calldata assets_
    )
        external
        returns (
            address[] memory rewardsList_,
            uint256[] memory claimedAmounts_
        )
    {
        uint256 len_ = assets_.length;
        uint256 num_ = 0;
        for (uint256 i = 0; i < len_; i++) {
            num_ += aTokenRewardsConfig[assets_[i]].length;
        }
        rewardsList_ = new address[](num_);
        claimedAmounts_ = new uint256[](num_);
        num_ = 0;
        for (uint256 i = 0; i < len_; i++) {
            RewardConfig[] memory rewardData_ = aTokenRewardsConfig[assets_[i]];
            for (uint256 j = 0; j < rewardData_.length; j++) {
                doTransferOut(
                    rewardData_[i].rwdToken,
                    msg.sender,
                    rewardData_[i].amount
                );
                rewardsList_[num_] = rewardData_[i].rwdToken;
                claimedAmounts_[num_] = rewardData_[i].amount;
                num_ += 1;
                emit RewardsClaimed(
                    msg.sender,
                    rewardData_[i].rwdToken,
                    msg.sender,
                    msg.sender,
                    rewardData_[i].amount
                );
            }
        }
    }

    function setRewardConfig(
        address aToken_,
        RewardConfig[] memory rewardConfigList_
    ) external {
        delete aTokenRewardsConfig[aToken_];
        for (uint256 i = 0; i < rewardConfigList_.length; i++) {
            aTokenRewardsConfig[aToken_].push(rewardConfigList_[i]);
            if (rwdTokenIdx[rewardConfigList_[i].rwdToken] == 0) {
                rewardList.push(rewardConfigList_[i].rwdToken);
                rwdTokenIdx[rewardConfigList_[i].rwdToken] = rewardList.length;
            }
        }
    }

    /**
     * @notice Withdraw tokens from the contract
     * @param token_ The reward token address
     * @param to_ Where to send the tokens
     * @param amount_ The number of tokens to withdraw
     */
    function withdrawToken(address token_, address to_, uint amount_) external {
        doTransferOut(token_, to_, amount_);
    }

    /**
     * @dev Safe IERC20MetadataUpgradeable transfer out
     */
    function doTransferOut(address token_, address to_, uint amount_) internal {
        bool success_ = IERC20MetadataUpgradeable(token_).transfer(
            to_,
            amount_
        );
        if (!success_) revert TransferOutFailed(to_, amount_);
    }
}
