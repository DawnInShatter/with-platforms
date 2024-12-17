// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {IERC20Upgradeable, SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ECDSAUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import {AdminHelperUpgradeable} from "../helpers/AdminHelperUpgradeable.sol";

/**
 * @title Faucet Contract
 */
contract OJEEFaucet is AdminHelperUpgradeable {
    using ECDSAUpgradeable for bytes32;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice The address used for the signature.
    address public signerAddress;
    mapping(bytes32 => bool) public signatureHistory;

    /// @notice Emitted when an admin updates the signerAddress.
    event UpdateSignerAddress(address indexed admin, address signerAddress);
    event EventClaimToken(
        address token,
        address to,
        uint256 amount,
        bytes signature
    );

    function initialize(address signerAddress_) public initializer {
        require(signerAddress_ != address(0), "Invalid zero address");

        __AdminHelper_init();
        signerAddress = signerAddress_;
    }

    function claimOJEE(
        address token_,
        address to_,
        uint256 amount_,
        uint256 expire_,
        bytes calldata signature_
    ) external {
        address signerAddress_ = keccak256(
            abi.encode(msg.sender, token_, to_, amount_, expire_)
        ).recover(signature_);
        require(signerAddress_ == signerAddress, "Invalid signerAddress");
        require(block.timestamp < expire_, "Expired");

        bytes32 signatureHash_ = keccak256(signature_);
        require(!signatureHistory[signatureHash_], "Claimed");

        signatureHistory[signatureHash_] = true;
        IERC20Upgradeable(token_).safeTransfer(to_, amount_);

        emit EventClaimToken(token_, to_, amount_, signature_);
    }

    /// @notice Update the signerAddress.
    /// @dev Emits an `UpdateSignerAddress` event.
    /// @dev Reverts if not called by an admin.
    /// @dev Reverts if the signerAddress is the zero address.
    /// @param signerAddress_ The address used for the signature.
    function updateSignerAddress(address signerAddress_) external onlyAdmin {
        require(signerAddress_ != address(0), "Invalid zero address");
        signerAddress = signerAddress_;

        emit UpdateSignerAddress(_msgSender(), signerAddress_);
    }

    function migrateToken(
        address token_,
        address recipient_,
        uint256 amount_
    ) external onlyAdmin {
        IERC20Upgradeable(token_).safeTransfer(recipient_, amount_);
    }
}
