// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract XCUpgradeableProxy is TransparentUpgradeableProxy {
    constructor(
        address logic_,
        address admin_,
        bytes memory data_
    ) payable TransparentUpgradeableProxy(logic_, admin_, data_) {}

    modifier onlyAdmin() {
        require(msg.sender == _getAdmin(), "Caller is not admin");
        _;
    }

    function getImplementation() external view onlyAdmin returns (address) {
        return _getImplementation();
    }
}
