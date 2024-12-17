// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStakedUSDe {
    // Events //
    /// @notice Event emitted when the rewards are received
    event RewardsReceived(uint256 amount);
    /// @notice Event emitted when the balance from an FULL_RESTRICTED_STAKER_ROLE user are redistributed
    event LockedAmountRedistributed(
        address indexed from,
        address indexed to,
        uint256 amount
    );
    /// @notice Event emitted when cooldown duration updates
    event CooldownDurationUpdated(uint24 previousDuration, uint24 newDuration);

    // Errors //
    /// @notice Error emitted shares or assets equal zero.
    error InvalidAmount();
    /// @notice Error emitted when owner attempts to rescue USDe tokens.
    error InvalidToken();
    /// @notice Error emitted when a small non-zero share amount remains, which risks donations attack
    error MinSharesViolation();
    /// @notice Error emitted when owner is not allowed to perform an operation
    error OperationNotAllowed();
    /// @notice Error emitted when there is still unvested amount
    error StillVesting();
    /// @notice Error emitted when owner or blacklist manager attempts to blacklist owner
    error CantBlacklistOwner();
    /// @notice Error emitted when the zero address is given
    error InvalidZeroAddress();

    /// @notice Error emitted when the shares amount to redeem is greater than the shares balance of the owner
    error ExcessiveRedeemAmount();
    /// @notice Error emitted when the shares amount to withdraw is greater than the shares balance of the owner
    error ExcessiveWithdrawAmount();
    /// @notice Error emitted when cooldown value is invalid
    error InvalidCooldown();
}
