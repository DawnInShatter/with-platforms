// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC20, ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract USDC is ERC20Permit {
    constructor(
        uint256 totalSupply_,
        address owner_
    ) ERC20Permit("USDC") ERC20("USDC", "USDC") {
        require(owner_ != address(0));

        _mint(owner_, totalSupply_);
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function toMint(address to_, uint256 amount_) external {
        _mint(to_, amount_);
    }

    function mint(
        address,
        address to,
        uint256 amount
    ) external returns (uint256) {
        _mint(to, amount);
        return amount;
    }
}
