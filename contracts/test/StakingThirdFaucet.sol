// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {AdminHelperUpgradeable} from "../helpers/AdminHelperUpgradeable.sol";
import {IWETH} from "../interfaces/IWETH.sol";

interface IFaucetMinter {
    function mint(
        address token,
        address to,
        uint256 amount
    ) external returns (uint256);
}

/**
 * @title Stand in CompoundV3 Comet Reward.
 * @author VIMWorld
 */
contract StakingThirdFaucet is AdminHelperUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice third faucet token => vimworld faucet cToken
    mapping(address => address) public thirdFaucetToVimworld;
    struct MintConfig {
        address minter;
        bool isNativeWrapper;
    }
    /// @notice vimworld/third faucet token => mint config
    mapping(address => MintConfig) public faucetMintConfig;

    error ErrorThirdFaucetNotEnough();
    error ErrorVimworldFaucetNotEnough();

    receive() external payable {}

    function initialize() public initializer {
        __AdminHelper_init();
    }

    /**
     * @notice Exchange third project faucet token to vimworld faucet token.
     * @param thirdFaucet_ The faucet token address of third project.
     * @param amount_ Exchange amount.
     */
    function exchangeVimworldFaucet(
        address thirdFaucet_,
        uint256 amount_
    ) external {
        address vimworldFaucet_ = thirdFaucetToVimworld[thirdFaucet_];
        if (vimworldFaucet_ == address(0)) {
            return;
        }
        IERC20Upgradeable(thirdFaucet_).safeTransferFrom(
            msg.sender,
            address(this),
            amount_
        );
        // mint vimworld token
        if (faucetMintConfig[vimworldFaucet_].isNativeWrapper) {
            IWETH(thirdFaucet_).withdraw(amount_);
            IWETH(vimworldFaucet_).deposit{value: amount_}();
        } else {
            _mintVimworldFaucetToken(vimworldFaucet_, amount_);
        }
        IERC20Upgradeable(vimworldFaucet_).safeTransfer(msg.sender, amount_);
    }

    /**
     * @notice Exchange vimworld faucet token to third project faucet token.
     * @param thirdFaucet_ The faucet token address of third project.
     * @param amount_ Exchange amount.
     */
    function exchangeThirdFaucet(
        address thirdFaucet_,
        uint256 amount_
    ) external {
        address vimworldFaucet_ = thirdFaucetToVimworld[thirdFaucet_];
        if (vimworldFaucet_ == address(0)) {
            return;
        }

        IERC20Upgradeable(vimworldFaucet_).safeTransferFrom(
            msg.sender,
            address(this),
            amount_
        );
        // mint
        if (faucetMintConfig[thirdFaucet_].isNativeWrapper) {
            IWETH(vimworldFaucet_).withdraw(amount_);
            IWETH(thirdFaucet_).deposit{value: amount_}();
        }
        if (
            IERC20Upgradeable(thirdFaucet_).balanceOf(address(this)) < amount_
        ) {
            revert ErrorThirdFaucetNotEnough();
        }
        IERC20Upgradeable(thirdFaucet_).safeTransfer(msg.sender, amount_);
    }

    function exchangeThirdFaucetUnlimited(
        address thirdFaucet_,
        address vimworldFaucet_,
        uint256 amount_
    ) external {
        if (thirdFaucet_ == vimworldFaucet_) {
            return;
        }
        IERC20Upgradeable(vimworldFaucet_).safeTransferFrom(
            msg.sender,
            address(this),
            amount_
        );
        // mint
        if (faucetMintConfig[thirdFaucet_].isNativeWrapper) {
            IWETH(vimworldFaucet_).withdraw(amount_);
            IWETH(thirdFaucet_).deposit{value: amount_}();
        }
        if (
            IERC20Upgradeable(thirdFaucet_).balanceOf(address(this)) < amount_
        ) {
            revert ErrorThirdFaucetNotEnough();
        }
        IERC20Upgradeable(thirdFaucet_).safeTransfer(msg.sender, amount_);
    }

    function _mintVimworldFaucetToken(
        address token_,
        uint256 amount_
    ) internal {
        uint256 balanceOf_ = IERC20Upgradeable(token_).balanceOf(address(this));
        if (balanceOf_ >= amount_) {
            return;
        }
        if (faucetMintConfig[token_].minter != address(0)) {
            IFaucetMinter(faucetMintConfig[token_].minter).mint(
                token_,
                address(this),
                amount_
            );
        } else {
            revert ErrorVimworldFaucetNotEnough();
        }
    }

    struct MintConfigParams {
        address faucetToken;
        address minter;
        bool isNativeWrapper;
    }

    function setVimworldFaucetMintConfigs(
        MintConfigParams[] calldata configList_
    ) external onlyAdmin {
        for (uint256 i = 0; i < configList_.length; i++) {
            faucetMintConfig[configList_[i].faucetToken] = MintConfig(
                configList_[i].minter,
                configList_[i].isNativeWrapper
            );
        }
    }

    /**
     * @notice Set third faucet token map to vimworld faucet token
     * @param faucetList_ [[vimworld faucet token, third faucet token], ]
     */
    function setThirdFacetMapToVimworld(
        address[2][] calldata faucetList_
    ) external onlyAdmin {
        for (uint256 i = 0; i < faucetList_.length; i++) {
            thirdFaucetToVimworld[faucetList_[i][1]] = faucetList_[i][0];
        }
    }
}
