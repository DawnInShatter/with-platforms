// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract ERC20Token is Ownable, ERC20Burnable {
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 totalSupply_,
        address owner_
    ) ERC20(name_, symbol_) {
        require(owner_ != address(0));

        _mint(owner_, totalSupply_);
    }
}
