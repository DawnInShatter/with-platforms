// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {AdminHelperUpgradeable} from "../../helpers/AdminHelperUpgradeable.sol";

contract TestRocketStorage is AdminHelperUpgradeable {
    // Storage maps
    mapping(bytes32 => address) private _addressStorage;

    /// @dev Construct RocketStorage
    constructor() {}

    function initialize() external initializer {
        __AdminHelper_init();
    }

    /// @param _key The key for the record
    function getAddress(bytes32 _key) external view returns (address r) {
        return _addressStorage[_key];
    }

    /// @param _key The key for the record
    function setAddress(bytes32 _key, address _value) external onlyAdmin {
        _addressStorage[_key] = _value;
    }

    /// @param _str The str for the record
    function getAddressWithString(
        string calldata _str
    ) external view returns (address) {
        return _addressStorage[keccak256(abi.encodePacked(_str))];
    }

    /// @param _str The str for the record
    function setAddressWithString(
        string calldata _str,
        address _value
    ) external onlyAdmin {
        _addressStorage[keccak256(abi.encodePacked(_str))] = _value;
    }
}
