// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {ShareERC20} from "../ShareERC20.sol";
import {AdminHelperUpgradeable} from "../../helpers/AdminHelperUpgradeable.sol";

contract TestCompoundV3 is ShareERC20, AdminHelperUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @dev The scale for factors
    uint64 internal constant FACTOR_SCALE = 1e18;
    /// @notice The point in the supply rates separating the low interest rate slope and the high interest rate slope (factor)
    /// @dev uint64
    uint256 public constant supplyKink = 9e17;

    /// @notice Per second supply interest rate slope applied when utilization is below kink (factor)
    /// @dev uint64
    uint256 public constant supplyPerSecondInterestRateSlopeLow = 2378234398;

    /// @notice Per second supply interest rate slope applied when utilization is above kink (factor)
    /// @dev uint64
    uint256 public constant supplyPerSecondInterestRateSlopeHigh = 114155251141;

    /// @notice Per second supply base interest rate (factor)
    /// @dev uint64
    uint256 public constant supplyPerSecondInterestRateBase = 0;
    /// @dev The scale for base tracking accrual
    uint64 public constant BASE_ACCRUAL_SCALE = 1e6;

    address public asset;
    uint256 public index;
    uint256 public updateTime;
    uint256 public perSecondApr; // 100% == 1e18
    uint256 internal _utilization;

    // Records a deposit made by a user
    event EventSupply(address indexed sender, uint256 amount);
    event EventWithdraw(
        address indexed sender,
        uint256 amount,
        uint256 withdrawAmount
    );
    event EventUpdateAPR(
        uint256 newIndex,
        uint256 newPerSecondAPR,
        uint256 updateTime
    );
    event EventRefreshAPR(
        uint256 newIndex,
        uint256 newPerSecondAPR,
        uint256 updateTime
    );

    error InvalidUInt64();

    function initialize(
        string memory name_,
        string memory symbol_,
        address token_
    ) public initializer {
        require(token_ != address(0), "Invalid zero address");
        __AdminHelper_init();
        __ShareERC20_init(name_, symbol_);

        asset = token_;
        index = 1e18;
        updateTime = block.timestamp;

        _utilization = 738440401139417055; // 73%
        perSecondApr = getSupplyRate(_utilization);
    }

    function decimals() public view override returns (uint8) {
        return IERC20MetadataUpgradeable(asset).decimals();
    }

    function baseAccrualScale() external pure returns (uint64) {
        return BASE_ACCRUAL_SCALE;
    }

    function supply(address asset_, uint256 amount_) external {
        require(amount_ != 0, "ZERO_DEPOSIT");

        _updateIndex();

        IERC20Upgradeable(asset_).safeTransferFrom(
            msg.sender,
            address(this),
            amount_
        );
        _mint(msg.sender, amount_);

        emit EventSupply(msg.sender, amount_);
    }

    function withdraw(
        address asset_,
        uint256 amount_
    ) external returns (uint256) {
        if (amount_ == 0) {
            return 0;
        }

        _updateIndex();

        _burn(msg.sender, amount_);

        IERC20Upgradeable(asset_).safeTransfer(msg.sender, amount_);

        emit EventWithdraw(msg.sender, amount_, amount_);
        return amount_;
    }

    function _mint(address account_, uint256 amount_) internal override {
        require(account_ != address(0), "ERC20: mint to the zero address");

        uint256 _sharesToMint = (amount_ * 1e18) / _getIndex();
        if (_sharesToMint == 0) {
            _sharesToMint = amount_;
        }
        _mintShare(account_, _sharesToMint);
        emit TransferShares(address(0), account_, _sharesToMint);
        emit Transfer(address(0), account_, amount_);
    }

    function _burn(address account_, uint256 amount_) internal virtual {
        require(account_ != address(0), "ERC20: mint to the zero address");

        uint256 _sharesToBurn = (amount_ * 1e18) / _getIndex();
        _burnShare(account_, _sharesToBurn);
        emit TransferShares(account_, address(0), _sharesToBurn);
        emit Transfer(account_, address(0), amount_);
    }

    function transferToVault(
        address account_,
        address token_
    ) external onlyAdmin {
        require(account_ != address(0), "RECOVER_VAULT_ZERO");

        uint256 balance;
        if (token_ == address(0)) {
            balance = address(this).balance;
            // Transfer replaced by call to prevent transfer gas amount issue
            (bool os, ) = account_.call{value: balance}("");
            require(os, "RECOVER_TRANSFER_FAILED");
        } else {
            IERC20Upgradeable token = IERC20Upgradeable(token_);
            balance = token.balanceOf(address(this));
            // safeTransfer comes from the overridden default implementation
            token.safeTransfer(account_, balance);
        }
    }

    function transferOutTokens(
        address account_,
        address token_,
        uint256 amount_
    ) external onlyAdmin {
        require(account_ != address(0), "RECOVER_VAULT_ZERO");

        if (token_ == address(0)) {
            // Transfer replaced by call to prevent transfer gas amount issue
            (bool os, ) = account_.call{value: amount_}("");
            require(os, "RECOVER_TRANSFER_FAILED");
        } else {
            IERC20Upgradeable token = IERC20Upgradeable(token_);
            // safeTransfer comes from the overridden default implementation
            token.safeTransfer(account_, amount_);
        }
    }

    /**
     * @notice Report reward, increase asset.
     * @param apr_ The report's APR, 100% = 10000.
     */
    function updateAPR(uint256 apr_) external onlyAdmin {
        require(apr_ <= 10000, "The apr is too high");
        uint256 newPerSecondApr_ = _getPerSecondAPR(apr_);

        _updateIndex();

        perSecondApr = newPerSecondApr_;

        emit EventUpdateAPR(index, newPerSecondApr_, block.timestamp);
    }

    function refreshAPR() external onlyAdmin {
        _updateIndex();
        perSecondApr = getSupplyRate(_utilization);

        emit EventUpdateAPR(index, perSecondApr, block.timestamp);
    }

    function setIndex(uint256 index_) external onlyAdmin {
        index = index_;
    }

    function setUtilization(uint256 utilization_) external onlyAdmin {
        _utilization = utilization_;
    }

    function submitWithoutToken(uint256 amount_) external onlyAdmin {
        _mint(msg.sender, amount_);
    }

    /**
     * @dev Note: Does not accrue interest first
     * @param utilization_ The utilization to check the supply rate for
     * @return The per second supply rate at `utilization`
     */
    function getSupplyRate(uint256 utilization_) public pure returns (uint64) {
        if (utilization_ <= supplyKink) {
            // interestRateBase + interestRateSlopeLow * utilization_
            return
                safe64(
                    supplyPerSecondInterestRateBase +
                        mulFactor(
                            supplyPerSecondInterestRateSlopeLow,
                            utilization_
                        )
                );
        } else {
            // interestRateBase + interestRateSlopeLow * kink + interestRateSlopeHigh * (utilization_ - kink)
            return
                safe64(
                    supplyPerSecondInterestRateBase +
                        mulFactor(
                            supplyPerSecondInterestRateSlopeLow,
                            supplyKink
                        ) +
                        mulFactor(
                            supplyPerSecondInterestRateSlopeHigh,
                            (utilization_ - supplyKink)
                        )
                );
        }
    }

    function getSharesByPooledEth(
        uint256 amount_
    ) public view returns (uint256) {
        return getShareByPooledToken(amount_);
    }

    /**
     * @dev Multiply a number by a factor
     */
    function mulFactor(
        uint256 n,
        uint256 factor
    ) internal pure returns (uint256) {
        return (n * factor) / FACTOR_SCALE;
    }

    function safe64(uint n) internal pure returns (uint64) {
        if (n > type(uint64).max) revert InvalidUInt64();
        return uint64(n);
    }

    function _getTotalPooledTokenBalance()
        internal
        view
        override
        returns (uint256)
    {
        uint256 totalShare_ = _getTotalShares();
        return (totalShare_ * _getIndex()) / 1e18;
    }

    function _getPerSecondAPR(uint256 apr_) internal pure returns (uint256) {
        // apr_: 100% == 10000
        return (apr_ * 1e18) / 3652425 / 86400;
    }

    function _updateIndex() internal {
        index = _getIndex();
        updateTime = block.timestamp;
    }

    function getIndex() external view returns (uint256) {
        return _getIndex();
    }

    function _getIndex() internal view returns (uint256) {
        return
            (index * (1e18 + (block.timestamp - updateTime) * perSecondApr)) /
            1e18;
    }
}
