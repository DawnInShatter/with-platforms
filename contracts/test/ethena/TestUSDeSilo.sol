// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title USDeSilo
 * @notice The Silo allows to store USDe during the stake cooldown process.
 */
contract TestUSDeSilo {
    IERC20 private immutable _USDE;

    constructor(address usde_) {
        _USDE = IERC20(usde_);
    }

    function withdraw(address to, uint256 amount) external {
        _USDE.transfer(to, amount);
    }
}
