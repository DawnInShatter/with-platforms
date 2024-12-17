// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {ShareERC20} from "../ShareERC20.sol";
import {AdminHelperUpgradeable} from "../../helpers/AdminHelperUpgradeable.sol";
import {DataTypesV3} from "../../interfaces/aave/DataTypesV3.sol";
import {IRewardsController} from "../../interfaces/aave/IRewardsController.sol";

contract TestAToken is ShareERC20, AdminHelperUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public asset;
    uint256 public index;
    uint256 public updateTime;
    uint256 public perSecondApr; // 100% == 1e18
    uint256 public aprAfterDeposit; // 100% = 1e18

    IRewardsController private _incentivesController;

    // Records a deposit made by a user
    event EventSupply(
        address indexed sender,
        uint256 amount,
        uint16 referralCode
    );
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

    function initialize(
        string memory name_,
        string memory symbol_,
        address token_,
        uint256 apr_,
        address incentivesController_
    ) public initializer {
        require(token_ != address(0), "Invalid zero address");
        require(incentivesController_ != address(0), "Invalid zero address");
        require(apr_ <= 10000, "The apr is too high");
        __AdminHelper_init();
        __ShareERC20_init(name_, symbol_);

        asset = token_;
        _incentivesController = IRewardsController(incentivesController_);
        index = 1e18;
        perSecondApr = _getPerSecondAPR(apr_);
        aprAfterDeposit = (perSecondApr * 3652425 * 86400 * 1e9) / 10000;
        updateTime = block.timestamp;
    }

    function UNDERLYING_ASSET_ADDRESS() external view returns (address) {
        return asset;
    }

    function decimals() public view override returns (uint8) {
        return IERC20MetadataUpgradeable(asset).decimals();
    }

    function getReserveDataExtend()
        public
        view
        returns (DataTypesV3.ReserveData memory)
    {
        DataTypesV3.ReserveConfigurationMap memory map_ = DataTypesV3
            .ReserveConfigurationMap(0);

        return
            DataTypesV3.ReserveData({
                configuration: map_,
                liquidityIndex: 0,
                currentLiquidityRate: (uint128(perSecondApr) *
                    3652425 *
                    86400 *
                    1e9) / 10000,
                variableBorrowIndex: 0,
                currentVariableBorrowRate: 0,
                currentStableBorrowRate: 0,
                lastUpdateTimestamp: 0,
                id: 0,
                liquidationGracePeriodUntil: 0,
                aTokenAddress: address(this),
                stableDebtTokenAddress: address(0),
                variableDebtTokenAddress: address(0),
                interestRateStrategyAddress: address(0),
                accruedToTreasury: 0,
                unbacked: 0,
                isolationModeTotalDebt: 0,
                virtualUnderlyingBalance: uint128(
                    IERC20Upgradeable(asset).balanceOf(address(this))
                )
            });
    }

    function getReserveData()
        public
        view
        returns (DataTypesV3.ReserveDataLegacy memory)
    {
        DataTypesV3.ReserveConfigurationMap memory map_ = DataTypesV3
            .ReserveConfigurationMap(2 ** 252);

        return
            DataTypesV3.ReserveDataLegacy({
                configuration: map_,
                liquidityIndex: 0,
                currentLiquidityRate: (uint128(perSecondApr) *
                    3652425 *
                    86400 *
                    1e9) / 10000,
                variableBorrowIndex: 0,
                currentVariableBorrowRate: 0,
                currentStableBorrowRate: 0,
                lastUpdateTimestamp: 0,
                id: 0,
                aTokenAddress: address(this),
                stableDebtTokenAddress: address(0),
                variableDebtTokenAddress: address(0),
                interestRateStrategyAddress: address(0),
                accruedToTreasury: 0,
                unbacked: 0,
                isolationModeTotalDebt: 0
            });
    }

    function getSharesByPooledEth(
        uint256 amount_
    ) public view returns (uint256) {
        return getShareByPooledToken(amount_);
    }

    function getIndex() external view returns (uint256) {
        return _getIndex();
    }

    function calculateInterestRates(
        DataTypesV3.CalculateInterestRatesParams calldata
    ) external view returns (uint256, uint256, uint256) {
        return (aprAfterDeposit, 0, 0);
    }

    /**
     * @notice Returns the address of the Incentives Controller contract
     * @return The address of the Incentives Controller
     */
    function getIncentivesController()
        external
        view
        virtual
        returns (IRewardsController)
    {
        return _incentivesController;
    }

    function supply(
        address account_,
        uint256 amount_,
        address,
        uint16 referralCode_
    ) external {
        require(amount_ != 0, "ZERO_DEPOSIT");

        _updateIndex();

        _mint(account_, amount_);

        emit EventSupply(account_, amount_, referralCode_);
    }

    function withdraw(
        uint256 amount_,
        address account_,
        address to_
    ) external returns (uint256) {
        if (amount_ == 0) {
            return 0;
        }

        _updateIndex();

        IERC20Upgradeable(asset).safeTransfer(to_, amount_);

        _burn(account_, amount_);

        emit EventWithdraw(account_, amount_, amount_);
        return amount_;
    }

    /**
     * @notice Sets a new Incentives Controller
     * @param controller the new Incentives controller
     */
    function setIncentivesController(
        IRewardsController controller
    ) external onlyAdmin {
        _incentivesController = controller;
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

    function setIndex(uint256 index_) external onlyAdmin {
        index = index_;
    }

    function setAprAfterDeposit(uint256 apr_) external onlyAdmin {
        aprAfterDeposit = (apr_ * 1e18 * 1e9) / 10000;
    }

    function submitWithoutToken(uint256 amount_) external onlyAdmin {
        _mint(msg.sender, amount_);
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

    function _getTotalPooledTokenBalance()
        internal
        view
        override
        returns (uint256)
    {
        uint256 totalShare_ = _getTotalShares();
        return (totalShare_ * _getIndex()) / 1e18;
    }

    function _getIndex() internal view returns (uint256) {
        return
            (index * (1e18 + (block.timestamp - updateTime) * perSecondApr)) /
            1e18;
    }

    function _getPerSecondAPR(uint256 apr_) internal pure returns (uint256) {
        // apr_: 100% == 10000, apr * 1e18 / 10000 / 365.2425/86400
        return (apr_ * 1e18) / 3652425 / 86400;
    }

    function _updateIndex() internal {
        index = _getIndex();
        updateTime = block.timestamp;
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
}
