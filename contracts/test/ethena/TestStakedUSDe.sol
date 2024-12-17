// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IStakedUSDe} from "./IStakedUSDe.sol";
import {TestUSDeSilo} from "./TestUSDeSilo.sol";

/**
 * @title StakedUSDe
 * @notice The StakedUSDe contract allows users to stake USDe tokens and earn a portion of protocol LST and perpetual yield that is allocated
 * to stakers by the Ethena DAO governance voted yield distribution algorithm.  The algorithm seeks to balance the stability of the protocol by funding
 * the protocol's insurance fund, DAO activities, and rewarding stakers with a portion of the protocol's yield.
 */
contract TestStakedUSDe is
    ReentrancyGuardUpgradeable,
    ERC20PermitUpgradeable,
    ERC4626Upgradeable,
    IStakedUSDe
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint24 public constant MAX_COOLDOWN_DURATION = 90 days;
    /// @notice Minimum non-zero shares amount to prevent donation attack
    uint256 public constant MIN_SHARES = 1 ether;
    TestUSDeSilo public immutable silo;

    uint24 public cooldownDuration;
    mapping(address => UserCooldown) public cooldowns;

    struct UserCooldown {
        uint104 cooldownEnd;
        uint152 underlyingAmount;
    }

    /* ------------- MODIFIERS ------------- */

    /// @notice ensure input amount nonzero
    modifier notZero(uint256 amount) {
        if (amount == 0) revert InvalidAmount();
        _;
    }

    constructor(address _usdeSilo) {
        if (_usdeSilo == address(0)) {
            revert InvalidZeroAddress();
        }
        silo = TestUSDeSilo(_usdeSilo);
    }

    function initialize(address _asset) public initializer {
        if (_asset == address(0)) {
            revert InvalidZeroAddress();
        }
        __ERC20_init("Staked USDe", "sUSDe");
        __ERC20Permit_init("sUSDe");
        __ERC4626_init(IERC20Upgradeable(_asset));
        __ReentrancyGuard_init();

        cooldownDuration = 10 minutes;
    }

    /* ------------- EXTERNAL ------------- */

    /**
     * @notice Allows the owner to transfer rewards from the controller contract into this contract.
     * @param amount The amount of rewards to transfer.
     */
    function transferInRewards(
        uint256 amount
    ) external nonReentrant notZero(amount) {
        // transfer assets from rewarder to this contract
        IERC20Upgradeable(asset()).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        emit RewardsReceived(amount);
    }

    /**
     * @dev See {IERC4626-withdraw}.
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address _owner
    ) public virtual override returns (uint256) {
        if (cooldownDuration > 0) {
            revert OperationNotAllowed();
        }
        return super.withdraw(assets, receiver, _owner);
    }

    /**
     * @dev See {IERC4626-redeem}.
     */
    function redeem(
        uint256 shares,
        address receiver,
        address _owner
    ) public virtual override returns (uint256) {
        if (cooldownDuration > 0) {
            revert OperationNotAllowed();
        }
        return super.redeem(shares, receiver, _owner);
    }

    /// @notice Claim the staking amount after the cooldown has finished. The address can only retire the full amount of assets.
    /// @dev unstake can be called after cooldown have been set to 0, to let accounts to be able to claim remaining assets locked at Silo
    /// @param receiver Address to send the assets by the staker
    function unstake(address receiver) external {
        UserCooldown storage userCooldown = cooldowns[msg.sender];
        uint256 assets = userCooldown.underlyingAmount;

        if (
            block.timestamp >= userCooldown.cooldownEnd || cooldownDuration == 0
        ) {
            userCooldown.cooldownEnd = 0;
            userCooldown.underlyingAmount = 0;

            silo.withdraw(receiver, assets);
        } else {
            revert InvalidCooldown();
        }
    }

    /// @notice redeem assets and starts a cooldown to claim the converted underlying asset
    /// @param assets assets to redeem
    function cooldownAssets(uint256 assets) external returns (uint256 shares) {
        if (assets > maxWithdraw(msg.sender)) revert ExcessiveWithdrawAmount();

        shares = previewWithdraw(assets);

        cooldowns[msg.sender].cooldownEnd =
            uint104(block.timestamp) +
            cooldownDuration;
        cooldowns[msg.sender].underlyingAmount += uint152(assets);

        _withdraw(msg.sender, address(silo), msg.sender, assets, shares);
    }

    /// @notice redeem shares into assets and starts a cooldown to claim the converted underlying asset
    /// @param shares shares to redeem
    function cooldownShares(uint256 shares) external returns (uint256 assets) {
        if (shares > maxRedeem(msg.sender)) revert ExcessiveRedeemAmount();

        assets = previewRedeem(shares);

        cooldowns[msg.sender].cooldownEnd =
            uint104(block.timestamp) +
            cooldownDuration;
        cooldowns[msg.sender].underlyingAmount += uint152(assets);

        _withdraw(msg.sender, address(silo), msg.sender, assets, shares);
    }

    /// @notice Set cooldown duration. If cooldown duration is set to zero, the StakedUSDeV2 behavior changes to follow ERC4626 standard and disables cooldownShares and cooldownAssets methods. If cooldown duration is greater than zero, the ERC4626 withdrawal and redeem functions are disabled, breaking the ERC4626 standard, and enabling the cooldownShares and the cooldownAssets functions.
    /// @param duration Duration of the cooldown
    function setCooldownDuration(uint24 duration) external {
        if (duration > MAX_COOLDOWN_DURATION) {
            revert InvalidCooldown();
        }

        uint24 previousDuration = cooldownDuration;
        cooldownDuration = duration;
        emit CooldownDurationUpdated(previousDuration, cooldownDuration);
    }

    /* ------------- PUBLIC ------------- */

    /**
     * @notice Returns the amount of USDe tokens that are vested in the contract.
     */
    function totalAssets() public view override returns (uint256) {
        return IERC20Upgradeable(asset()).balanceOf(address(this));
    }

    /// @dev Necessary because both ERC20 (from ERC20PermitUpgradeable) and ERC4626 declare decimals()
    function decimals()
        public
        pure
        override(ERC4626Upgradeable, ERC20Upgradeable)
        returns (uint8)
    {
        return 18;
    }

    /* ------------- INTERNAL ------------- */

    /// @notice ensures a small non-zero amount of shares does not remain, exposing to donation attack
    function _checkMinShares() internal view {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply > 0 && _totalSupply < MIN_SHARES)
            revert MinSharesViolation();
    }

    /**
     * @dev Deposit/mint common workflow.
     * @param caller sender of assets
     * @param receiver where to send shares
     * @param assets assets to deposit
     * @param shares shares to mint
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override nonReentrant notZero(assets) notZero(shares) {
        super._deposit(caller, receiver, assets, shares);
        _checkMinShares();
    }

    /**
     * @dev Withdraw/redeem common workflow.
     * @param caller tx sender
     * @param receiver where to send assets
     * @param _owner where to burn shares from
     * @param assets asset amount to transfer out
     * @param shares shares to burn
     */
    function _withdraw(
        address caller,
        address receiver,
        address _owner,
        uint256 assets,
        uint256 shares
    ) internal override nonReentrant notZero(assets) notZero(shares) {
        super._withdraw(caller, receiver, _owner, assets, shares);
        _checkMinShares();
    }
}
