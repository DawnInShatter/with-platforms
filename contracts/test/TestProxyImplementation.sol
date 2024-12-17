// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/**
 * @dev Testing contract
 */
contract TestProxyImplementation is Initializable {
    uint256 public testParam1;
    address public testParam2;

    function initialize(uint256 param1_, address param2_) public initializer {
        testParam1 = param1_;
        testParam2 = param2_;
    }

    /**
     * @notice Function to change testParam1.
     */
    function changTestParam1(uint256 newValue) public {
        testParam1 = newValue;
    }

    /**
     * @notice Function to change testParam2.
     */
    function changTestParam2(address newValue) public {
        testParam2 = newValue;
    }
}
