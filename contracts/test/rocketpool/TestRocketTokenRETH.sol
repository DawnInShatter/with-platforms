// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {AdminHelperUpgradeable} from "../../helpers/AdminHelperUpgradeable.sol";
import {TestRocketStorage} from "./TestRocketStorage.sol";
import {TestRocketDepositPool} from "./TestRocketDepositPool.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

// rETH is a tokenised stake in the Rocket Pool network
// rETH is backed by ETH (subject to liquidity) at a variable exchange rate

contract TestRocketTokenRETH is ERC20Upgradeable, AdminHelperUpgradeable {
    // Libs
    using SafeMath for uint;

    uint256 public constant CALCBASE = 1 ether;

    // The main storage contract where primary persistant storage is maintained
    TestRocketStorage public rocketStorage;

    // Events
    event EtherDeposited(address indexed from, uint256 amount, uint256 time);
    event TokensMinted(
        address indexed to,
        uint256 amount,
        uint256 ethAmount,
        uint256 time
    );
    event TokensBurned(
        address indexed from,
        uint256 amount,
        uint256 ethAmount,
        uint256 time
    );

    function initialize(
        TestRocketStorage _rocketStorageAddress
    ) public initializer {
        __AdminHelper_init();
        __ERC20_init("Rocket Pool ETH", "rETH");

        rocketStorage = TestRocketStorage(_rocketStorageAddress);
    }

    // Receive an ETH deposit from a minipool or generous individual
    receive() external payable {
        // Emit ether deposited event
        emit EtherDeposited(msg.sender, msg.value, block.timestamp);
    }

    // Deposit excess ETH from deposit pool
    // Only accepts calls from the RocketDepositPool contract
    function depositExcess()
        external
        payable
        onlyLatestContract("rocketDepositPool", msg.sender)
    {
        // Emit ether deposited event
        emit EtherDeposited(msg.sender, msg.value, block.timestamp);
    }

    // Mint rETH
    // Only accepts calls from the RocketDepositPool contract
    function mint(
        uint256 _ethAmount,
        address _to
    ) external onlyLatestContract("rocketDepositPool", msg.sender) {
        // Get rETH amount
        uint256 rethAmount = getRethValue(_ethAmount);
        // Check rETH amount
        require(rethAmount > 0, "Invalid token mint amount");
        // Update balance & supply
        _mint(_to, rethAmount);
        // Emit tokens minted event
        emit TokensMinted(_to, rethAmount, _ethAmount, block.timestamp);
    }

    // Burn rETH for ETH
    function burn(uint256 _rethAmount) external {
        // Check rETH amount
        require(_rethAmount > 0, "Invalid token burn amount");
        require(
            balanceOf(msg.sender) >= _rethAmount,
            "Insufficient rETH balance"
        );
        // Get ETH amount
        uint256 ethAmount = getEthValue(_rethAmount);
        // Get & check ETH balance
        uint256 ethBalance = getTotalCollateral();
        require(
            ethBalance >= ethAmount,
            "Insufficient ETH balance for exchange"
        );
        // Update balance & supply
        _burn(msg.sender, _rethAmount);
        // Withdraw ETH from deposit pool if required
        _withdrawDepositCollateral(ethAmount);
        // Transfer ETH to sender
        (bool os, ) = msg.sender.call{value: ethAmount}("");
        require(os, "RECOVER_TRANSFER_FAILED");
        // Emit tokens burned event
        emit TokensBurned(msg.sender, _rethAmount, ethAmount, block.timestamp);
    }

    // Calculate the amount of ETH backing an amount of rETH
    function getEthValue(uint256 _rethAmount) public view returns (uint256) {
        TestRocketDepositPool rocketDepositPool = TestRocketDepositPool(
            _getContractAddress("rocketDepositPool")
        );
        uint256 totalEthBalance = rocketDepositPool.getBalance();
        uint256 rethSupply = totalSupply();
        // Use 1:1 ratio if no rETH is minted
        if (rethSupply == 0) {
            return _rethAmount;
        }
        // Calculate and return
        return _rethAmount.mul(totalEthBalance).div(rethSupply);
    }

    // Calculate the amount of rETH backed by an amount of ETH
    function getRethValue(uint256 _ethAmount) public view returns (uint256) {
        TestRocketDepositPool rocketDepositPool = TestRocketDepositPool(
            _getContractAddress("rocketDepositPool")
        );
        uint256 totalEthBalance = rocketDepositPool.getBalance();
        uint256 rethSupply = totalSupply();
        // Use 1:1 ratio if no rETH is minted
        if (rethSupply == 0) {
            return _ethAmount;
        }
        // Check network ETH balance
        require(
            totalEthBalance > 0,
            "Cannot calculate rETH token amount while total network balance is zero"
        );
        // Calculate and return
        return _ethAmount.mul(rethSupply).div(totalEthBalance);
    }

    // Get the total amount of collateral available
    // Includes rETH contract balance & excess deposit pool balance
    function getTotalCollateral() public view returns (uint256) {
        TestRocketDepositPool rocketDepositPool = TestRocketDepositPool(
            _getContractAddress("rocketDepositPool")
        );
        return rocketDepositPool.getExcessBalance().add(address(this).balance);
    }

    // Get the current ETH collateral rate
    // Returns the portion of rETH backed by ETH in the contract as a fraction of 1 ether
    function getCollateralRate() public view returns (uint256) {
        uint256 totalEthValue = getEthValue(totalSupply());
        if (totalEthValue == 0) {
            return CALCBASE;
        }
        return CALCBASE.mul(address(this).balance).div(totalEthValue);
    }

    // Get the current ETH : rETH exchange rate
    // Returns the amount of ETH backing 1 rETH
    function getExchangeRate() public view returns (uint256) {
        return getEthValue(1 ether);
    }

    // Withdraw ETH from the deposit pool for collateral if required
    function _withdrawDepositCollateral(uint256 _ethRequired) private {
        // Check rETH contract balance
        uint256 ethBalance = address(this).balance;
        if (ethBalance >= _ethRequired) {
            return;
        }
        // Withdraw
        TestRocketDepositPool rocketDepositPool = TestRocketDepositPool(
            _getContractAddress("rocketDepositPool")
        );
        rocketDepositPool.withdrawExcessBalance(_ethRequired.sub(ethBalance));
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

    /**
     * @dev Throws if called by any sender that doesn't match one of the supplied contract or is the latest version of that contract
     */
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
