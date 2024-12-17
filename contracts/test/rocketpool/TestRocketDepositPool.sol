// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {AdminHelperUpgradeable} from "../../helpers/AdminHelperUpgradeable.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {TestRocketStorage} from "./TestRocketStorage.sol";
import {TestRocketTokenRETH} from "./TestRocketTokenRETH.sol";

/// @notice Accepts user deposits and mints rETH; handles assignment of deposited ETH to minipools
contract TestRocketDepositPool is AdminHelperUpgradeable {
    // Libs
    using SafeMath for uint256;

    // Immutables
    TestRocketTokenRETH public rocketTokenRETH;

    // The main storage contract where primary persistant storage is maintained
    TestRocketStorage public rocketStorage;

    uint256 public ethAsset;
    uint256 public depositETHFee;

    // Events
    event DepositReceived(address indexed from, uint256 amount, uint256 time);
    event DepositRecycled(address indexed from, uint256 amount, uint256 time);
    event DepositAssigned(
        address indexed minipool,
        uint256 amount,
        uint256 time
    );
    event ExcessWithdrawn(address indexed to, uint256 amount, uint256 time);
    event HandleReport(
        uint256 newExtraAmount,
        uint256 amount,
        uint256 reportTime,
        uint256 apr
    );

    // Modifiers
    modifier onlyThisLatestContract() {
        // Compiler can optimise out this keccak at compile time
        require(
            address(this) ==
                _getAddress(keccak256("contract.addressrocketDepositPool")),
            "Invalid or outdated contract"
        );
        _;
    }

    function initialize(
        TestRocketStorage _rocketStorageAddress
    ) public initializer {
        __AdminHelper_init();

        rocketStorage = TestRocketStorage(_rocketStorageAddress);
        rocketTokenRETH = TestRocketTokenRETH(
            payable(_getContractAddress("rocketTokenRETH"))
        );
    }

    /// @notice Deposits ETH into Rocket Pool and mints the corresponding amount of rETH to the caller
    function deposit() external payable onlyThisLatestContract {
        // Calculate deposit fee
        uint256 depositFee = msg.value.mul(5).div(10000);
        uint256 depositNet = msg.value.sub(depositFee);
        // Mint rETH to user account
        rocketTokenRETH.mint(depositNet, msg.sender);
        // Emit deposit received event
        emit DepositReceived(msg.sender, msg.value, block.timestamp);
        // Process deposit
        _processDeposit(depositNet, depositFee);
    }

    function depositWithoutToken(uint256 amount_) external onlyAdmin {
        rocketTokenRETH.mint(amount_, msg.sender);
        _processDeposit(amount_, 0);
    }

    /// @dev Withdraw excess deposit pool balance for rETH collateral
    /// @param _amount The amount of excess ETH to withdraw
    function withdrawExcessBalance(
        uint256 _amount
    )
        external
        onlyThisLatestContract
        onlyLatestContract("rocketTokenRETH", msg.sender)
    {
        // Check amount
        require(
            _amount <= address(this).balance,
            "Insufficient excess balance for withdrawal"
        );
        _processWithdraw(_amount);
        // Transfer to rETH contract
        rocketTokenRETH.depositExcess{value: _amount}();
        // Emit excess withdrawn event
        emit ExcessWithdrawn(msg.sender, _amount, block.timestamp);
    }

    /**
     * @notice Report reward, increase asset.
     * @param apr_ The report's APR, 100% = 10000.
     */
    function handleReport(uint256 apr_) external onlyAdmin {
        require(apr_ >= 10, "The apr is too low");
        require(apr_ <= 500, "The apr is too high");
        uint256 totalBalance_ = getBalance();
        uint256 rewardAmount_ = (totalBalance_ * apr_) / 3652425;
        ethAsset += rewardAmount_;

        emit HandleReport(ethAsset, rewardAmount_, block.timestamp, apr_);
    }

    function setETHAsset(uint256 amount_) external onlyAdmin {
        ethAsset = amount_;
    }

    /// @notice Returns the current deposit pool balance
    function getBalance() public view returns (uint256) {
        return ethAsset;
    }

    /// @notice Excess deposit pool balance (in excess of minipool queue capacity)
    function getExcessBalance() public view returns (uint256) {
        return address(this).balance;
    }

    /// @dev Process a deposit
    function _processDeposit(uint256 amount_, uint256 feeAmount_) private {
        ethAsset += amount_;
        depositETHFee += feeAmount_;
    }

    /// @dev Process a withdraw
    function _processWithdraw(uint256 amount_) private {
        ethAsset -= amount_;
    }

    /// @dev Get the address of a network contract by name
    function _getContractAddress(
        string memory _contractName
    ) internal view returns (address) {
        // Get the current contract address
        address contractAddress = _getAddress(
            keccak256(abi.encodePacked("contract.address", _contractName))
        );
        // Check it
        require(contractAddress != address(0x0), "Contract not found");
        // Return
        return contractAddress;
    }

    function _getAddress(bytes32 _key) internal view returns (address) {
        return rocketStorage.getAddress(_key);
    }

    modifier onlyLatestContract(
        string memory _contractName,
        address _contractAddress
    ) {
        require(
            _contractAddress ==
                _getAddress(
                    keccak256(
                        abi.encodePacked("contract.address", _contractName)
                    )
                ),
            "Invalid or outdated contract"
        );
        _;
    }
}
